//! REST endpointy — registrace, prekey bundle, sender cert.
//! Chybové odpovědi nikdy neleakují interní detail; logy bez identifikátorů.

use std::net::SocketAddr;
use std::sync::Arc;

use axum::body::{Body, Bytes};
use axum::extract::{ConnectInfo, FromRequest, Path, Request, State};
use axum::http::{header, HeaderMap, HeaderValue, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::{Extension, Json};
use base64::prelude::*;
use libsignal_protocol::PublicKey;
use rand::RngCore;
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::blocking::{self, AddressError, Retire};
use crate::fingerprint::Fingerprint;
use crate::limits::RegisterLimits;
use crate::pow::{Mode as PowMode, Verdict};
use crate::state::AppState;

/// Hlavička se strojovou značkou chyby. Appka podle ní rozliší třeba 403
/// relaye (zablokovaná identita) od 403 bezpečnostní vrstvy na edgi.
const ERROR_TAG_HEADER: &str = "x-sepot-error";
pub(crate) const TAG_IDENTITY_PROOF: &str = "identity-proof";
pub(crate) const TAG_IDENTITY_BLOCKED: &str = "identity-blocked";
pub(crate) const TAG_ADDRESS_TAKEN: &str = "address-taken";
pub(crate) const TAG_RETRY: &str = "retry";
pub(crate) const TAG_DEVICE_GONE: &str = "device-gone";
const TEXT_INVALID_IDENTITY_KEY: &str = "neplatný identity klíč";

/// Chybová odpověď REST: stav, text pro člověka a volitelná značka.
#[derive(Debug)]
pub(crate) struct ApiError {
    pub status: StatusCode,
    pub message: String,
    pub tag: Option<&'static str>,
    /// Za jak dlouho má klient zkusit znovu (hlavička Retry-After).
    pub retry_after: Option<std::time::Duration>,
}

impl ApiError {
    fn tagged(status: StatusCode, message: &str, tag: &'static str) -> Self {
        Self {
            status,
            message: message.into(),
            tag: Some(tag),
            retry_after: None,
        }
    }

    fn too_many(wait: std::time::Duration) -> Self {
        Self {
            status: StatusCode::TOO_MANY_REQUESTS,
            message: crate::limits::TEXT_TOO_MANY.into(),
            tag: None,
            retry_after: Some(wait),
        }
    }
}

impl From<(StatusCode, String)> for ApiError {
    fn from((status, message): (StatusCode, String)) -> Self {
        Self {
            status,
            message,
            tag: None,
            retry_after: None,
        }
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let mut response = (self.status, self.message).into_response();
        if let Some(tag) = self.tag {
            response
                .headers_mut()
                .insert(ERROR_TAG_HEADER, HeaderValue::from_static(tag));
        }
        if let Some(wait) = self.retry_after {
            response
                .headers_mut()
                .insert(header::RETRY_AFTER, crate::limits::retry_after(wait));
        }
        response
    }
}

type ApiResult<T> = Result<T, ApiError>;

fn internal<E: std::fmt::Display>(e: E) -> ApiError {
    tracing::warn!("interní chyba: {e}");
    (
        StatusCode::INTERNAL_SERVER_ERROR,
        "interní chyba".to_string(),
    )
        .into()
}

fn bad(msg: &str) -> ApiError {
    (StatusCode::BAD_REQUEST, msg.to_string()).into()
}

fn address_taken() -> ApiError {
    ApiError::tagged(
        StatusCode::CONFLICT,
        "doručovací adresa není k dispozici",
        TAG_ADDRESS_TAKEN,
    )
}

fn b64(name: &str, value: &str, expect_len: Option<usize>) -> ApiResult<Vec<u8>> {
    let bytes = BASE64_STANDARD
        .decode(value)
        .map_err(|_| bad(&format!("pole {name} není platný base64")))?;
    if let Some(len) = expect_len {
        if bytes.len() != len {
            return Err(bad(&format!("pole {name} má špatnou délku")));
        }
    }
    Ok(bytes)
}

pub async fn health() -> Json<serde_json::Value> {
    Json(serde_json::json!({ "status": "ok" }))
}

/// Jak dlouho platí výsledek sondy DB. `/v1/ready` je bez přihlášení a bez
/// limitu (volají ho sondy z vnitřní sítě); kdyby každý dotaz stál spojení
/// z poolu, šlo by jím pool vyčerpat. Dvě sekundy sondám monitoringu nevadí.
const READY_PROBE_TTL: std::time::Duration = std::time::Duration::from_secs(2);
const READY_PROBE_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(1);

/// Poslední výsledek sondy DB, sdílený všemi dotazy na `/v1/ready`.
#[derive(Default)]
pub struct ReadyProbe(tokio::sync::Mutex<Option<(std::time::Instant, bool)>>);

impl ReadyProbe {
    /// Zámek se drží i přes dotaz: souběžné požadavky počkají na jeden
    /// výsledek, místo aby každý poslal vlastní.
    pub async fn check(&self, pool: &sqlx::PgPool) -> bool {
        let mut last = self.0.lock().await;
        if let Some((at, ready)) = *last {
            if at.elapsed() < READY_PROBE_TTL {
                return ready;
            }
        }
        let probe =
            tokio::time::timeout(READY_PROBE_TIMEOUT, sqlx::query("SELECT 1").execute(pool)).await;
        let ready = matches!(probe, Ok(Ok(_)));
        *last = Some((std::time::Instant::now(), ready));
        ready
    }
}

/// Readiness: health je jen „proces žije", tohle ověří i DB.
/// Pro sondy monitoringu — DB mimo provoz = 503, ne falešné 200.
pub async fn ready(State(state): State<Arc<AppState>>) -> ApiResult<Json<serde_json::Value>> {
    if state.ready_probe.check(&state.pool).await {
        Ok(Json(serde_json::json!({ "status": "ready" })))
    } else {
        Err((
            StatusCode::SERVICE_UNAVAILABLE,
            "databáze neodpovídá".to_string(),
        )
            .into())
    }
}

/// Veřejné informace o relayi. `source` + `revision` plní AGPL §13 — kdo
/// s relayem mluví, má vědět, který zdroj právě běží. `identity-block`:
/// relay vynucuje blokace a vrací 403/410 se značkou, appka podle toho
/// volí texty. `inactive_registration_days` je lhůta úklidu neaktivních
/// registrací, null = úklid vypnutý.
pub async fn server_info(State(state): State<Arc<AppState>>) -> Json<serde_json::Value> {
    let mut capabilities = vec![
        "pqxdh",
        "sealed-sender",
        "prekey-upload",
        "identity-reclaim",
        // Relay rozumí hlavičce X-Sepot-Body-SHA256 (podpis kryje i tělo).
        "auth-body-hash",
    ];
    if state.pow.mode() != PowMode::Off {
        capabilities.push("register-pow");
    }
    capabilities.push("identity-block");
    let inactive_registration_days = state
        .limits
        .inactive_cleanup
        .then_some(crate::cleanup::INACTIVE_REGISTRATION_DAYS);
    Json(serde_json::json!({
        "frame_version": 1,
        "trust_root": BASE64_STANDARD.encode(&state.certs.trust_root_public),
        "capabilities": capabilities,
        "register_pow": state.pow.mode().as_str(),
        "inactive_registration_days": inactive_registration_days,
        "source": state.source_url,
        "revision": state.revision,
    }))
}

fn unix_now() -> u64 {
    chrono::Utc::now().timestamp().max(0) as u64
}

// ── GET /v1/register/challenge ─────────────────────────────────────────

/// Výzva proof-of-work pro registraci (pow.rs). `no-store`: každá výzva je
/// jednorázová, sdílená cache by ji rozdala víc klientům.
pub async fn register_challenge(State(state): State<Arc<AppState>>) -> Response {
    if state.pow.mode() == PowMode::Off {
        return (StatusCode::NOT_FOUND, "proof-of-work je vypnutý").into_response();
    }
    let now = unix_now();
    let challenge = state.pow.issue(now);
    let mut response = Json(serde_json::json!({
        "algorithm": "sha256-v1",
        "challenge": BASE64_URL_SAFE_NO_PAD.encode(challenge.token),
        "bits": challenge.bits,
        "expires_at": challenge.expires_at,
        // relativně: hodiny telefonu bývají mimo, platnost si klient měří sám
        "expires_in": challenge.expires_at - now,
        "mode": state.pow.mode().as_str(),
    }))
    .into_response();
    response
        .headers_mut()
        .insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
    response
}

/// Hlavička `X-Sepot-Body-SHA256: <hex>`: otisk těla, který klient zahrnul
/// do podpisu X-Sepot-Auth nebo X-Sepot-Identity-Proof.
pub(crate) const BODY_HASH_HEADER: &str = "x-sepot-body-sha256";
const SHA256_LEN: usize = 32;

/// K čemu se klient podpisem zavázal: k otisku těla, nebo jen k cestě a
/// času (klienti do 1.2.7).
///
/// Podpis jen nad cestou a časem jde v pětiminutovém okně použít znovu
/// s jiným tělem, když ho někdo po cestě zachytí. S hlavičkou je otisk těla
/// součástí podepsané zprávy a relay ho s tělem porovná. Hlavičku nejde
/// z požadavku jen vypustit: podpis je nad zprávou s otiskem a ke zprávě bez
/// něj nesedí. Staří klienti ji neposílají a mají ochranu jako dosud.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct BodyClaim(Option<[u8; SHA256_LEN]>);

impl BodyClaim {
    /// `None` = hlavička je přítomná, ale není to otisk.
    fn from_headers(headers: &HeaderMap) -> Option<Self> {
        let Some(value) = headers.get(BODY_HASH_HEADER) else {
            return Some(Self(None));
        };
        let digest = hex::decode(value.as_bytes()).ok()?;
        Some(Self(Some(digest.try_into().ok()?)))
    }

    /// Zpráva, kterou klient podepsal.
    fn message(&self, method_path: &str, ts: i64) -> String {
        match &self.0 {
            Some(digest) => format!("{method_path}\n{ts}\n{}", hex::encode(digest)),
            None => format!("{method_path}\n{ts}"),
        }
    }

    /// Sedí tělo k tomu, co klient podepsal? Bez závazku sedí každé.
    pub(crate) fn matches(&self, body_sha256: &[u8; SHA256_LEN]) -> bool {
        self.0.is_none_or(|claimed| &claimed == body_sha256)
    }
}

pub(crate) const TEXT_BODY_MISMATCH: &str = "tělo požadavku nesedí k podpisu";

/// JSON tělo i s otiskem bajtů, jak přišly. Chová se jako `Json` (stejná
/// odmítnutí i strop velikosti), jen si tělo napřed přečte celé.
pub struct HashedJson<T> {
    pub value: T,
    pub sha256: [u8; SHA256_LEN],
}

impl<S, T> FromRequest<S> for HashedJson<T>
where
    S: Send + Sync,
    T: DeserializeOwned,
{
    type Rejection = Response;

    async fn from_request(request: Request, state: &S) -> Result<Self, Self::Rejection> {
        let (parts, body) = request.into_parts();
        let bytes = Bytes::from_request(Request::from_parts(parts.clone(), body), state)
            .await
            .map_err(IntoResponse::into_response)?;
        let sha256 = Sha256::digest(&bytes).into();
        let Json(value) =
            Json::<T>::from_request(Request::from_parts(parts, Body::from(bytes)), state)
                .await
                .map_err(IntoResponse::into_response)?;
        Ok(Self { value, sha256 })
    }
}

/// Ověří hlavičku `X-Sepot-Identity-Proof: <ts_ms>.<sig_b64>` — podpis
/// identity klíčem nad `"<method_path>\n<ts_ms>"` (s `X-Sepot-Body-SHA256`
/// ještě `"\n<otisk hex>"`), stejné okno jako X-Sepot-Auth. Důkaz držení
/// privátního klíče bez znalosti device_uuid: obnova ze 24 slov na novém
/// telefonu nemá nic jiného. Vrací, k čemu se klient zavázal; `None` =
/// důkaz neplatí.
fn identity_proof_valid(
    headers: &HeaderMap,
    identity: &PublicKey,
    method_path: &str,
) -> Option<BodyClaim> {
    let header = headers
        .get("x-sepot-identity-proof")
        .and_then(|v| v.to_str().ok())?;
    let (ts_str, sig_b64) = header.split_once('.')?;
    let ts = ts_str.parse::<i64>().ok()?;
    let signature = BASE64_STANDARD.decode(sig_b64).ok()?;
    let now_ms = chrono::Utc::now().timestamp_millis();
    if now_ms.abs_diff(ts) > AUTH_WINDOW_MS as u64 {
        return None;
    }
    let claim = BodyClaim::from_headers(headers)?;
    identity
        .verify_signature(claim.message(method_path, ts).as_bytes(), &signature)
        .then_some(claim)
}

// ── POST /v1/register ──────────────────────────────────────────────────

#[derive(Deserialize)]
pub struct PreKeyIn {
    pub key_id: i32,
    pub public_key: String,
    #[serde(default)]
    pub signature: Option<String>,
    #[serde(default)]
    pub is_last_resort: bool,
}

#[derive(Deserialize)]
pub struct RegisterIn {
    pub identity_key: String,
    pub device_id: i32,
    pub registration_id: i32,
    pub delivery_address: String,
    pub signed_prekey: PreKeyIn,
    pub kyber_prekey: PreKeyIn,
    #[serde(default)]
    pub one_time_prekeys: Vec<PreKeyIn>,
}

#[derive(Serialize)]
pub struct RegisterOut {
    pub account_id: String,
    pub device_uuid: String,
}

/// Strop OTP klíčů v jedné registraci (klient posílá 100).
const MAX_ONE_TIME_PREKEYS: usize = 100;

/// Limit registrací se vybírá až v handleru: bucket per IP závisí na tom,
/// jestli klient přinesl platný proof-of-work, a ten je vázaný na identity
/// klíč z těla. Ověření PoW je jedna HMAC a jedna SHA-256, takže pořadí
/// „parsovat → ověřit → limit → podpisy a DB“ nic drahého nepouští dřív.
pub async fn register(
    State(state): State<Arc<AppState>>,
    Extension(limits): Extension<Arc<RegisterLimits>>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    HashedJson {
        value: body,
        sha256: body_sha256,
    }: HashedJson<RegisterIn>,
) -> Response {
    if state.limits.registration_paused {
        return (
            StatusCode::SERVICE_UNAVAILABLE,
            [(header::RETRY_AFTER, "300")],
            "registrace jsou dočasně pozastavené, zkus to za pár minut",
        )
            .into_response();
    }
    let identity_key = match b64("identity_key", &body.identity_key, Some(33)) {
        Ok(key) => key,
        Err(e) => return e.into_response(),
    };
    let with_pow = match (state.pow.mode(), state.pow.verify(&headers, &identity_key, unix_now())) {
        (PowMode::Off, _) => false,
        (_, Verdict::Valid) => true,
        (PowMode::Optional, Verdict::Missing) => false,
        (PowMode::Optional, Verdict::Invalid(why)) => {
            // Prošlá nebo poškozená výzva v režimu optional = registrace jako
            // bez PoW (běžný limit), ne chyba: starší výzva po restartu relaye
            // nesmí člověka zablokovat.
            tracing::debug!(why, "neplatný proof-of-work, běžný limit");
            false
        }
        (PowMode::Required, verdict) => {
            if let Verdict::Invalid(why) = verdict {
                tracing::debug!(why, "neplatný proof-of-work");
            }
            return (
                StatusCode::PRECONDITION_REQUIRED,
                "registrace vyžaduje proof-of-work (GET /v1/register/challenge)",
            )
                .into_response();
        }
    };
    // Tady jen limit na adresu; globální strop bere až `register_device`
    // po ověření podpisů a důkazu držení klíče.
    let limiter = if with_pow { &limits.pow } else { &limits.base };
    if let Err(wait) = limiter.check(peer.ip(), &headers) {
        return crate::limits::too_many(wait);
    }
    match register_device(&state, &headers, identity_key, body, &body_sha256).await {
        Ok(created) => {
            state.pow.note_registration();
            tracing::info!(pow = with_pow, "nová registrace zařízení");
            created.into_response()
        }
        Err(e) => e.into_response(),
    }
}

pub(crate) async fn register_device(
    state: &AppState,
    headers: &HeaderMap,
    identity_key: Vec<u8>,
    body: RegisterIn,
    body_sha256: &[u8; SHA256_LEN],
) -> ApiResult<(StatusCode, Json<RegisterOut>)> {
    if body.one_time_prekeys.len() > MAX_ONE_TIME_PREKEYS {
        return Err(bad("příliš mnoho one-time prekeys"));
    }
    // libsignal DeviceId je 1..=127; registration_id kladné 14bitové číslo.
    // Mimo rozsah by registrace prošla a GET /v1/certificate pak padal na 500.
    if !(1..=127).contains(&body.device_id) || !(1..=16_383).contains(&body.registration_id) {
        return Err(bad("device_id nebo registration_id mimo rozsah"));
    }
    let delivery_address = b64("delivery_address", &body.delivery_address, Some(32))?;
    let spk_pub = b64("signed_prekey.public_key", &body.signed_prekey.public_key, Some(33))?;
    let spk_sig = b64(
        "signed_prekey.signature",
        body.signed_prekey.signature.as_deref().ok_or_else(|| bad("chybí podpis signed prekey"))?,
        Some(64),
    )?;
    let kyber_pub = b64("kyber_prekey.public_key", &body.kyber_prekey.public_key, None)?;
    let kyber_sig = b64(
        "kyber_prekey.signature",
        body.kyber_prekey.signature.as_deref().ok_or_else(|| bad("chybí podpis kyber prekey"))?,
        Some(64),
    )?;

    // Hygiena: podpisy prekeys musí sedět k identity klíči už při uploadu.
    let identity =
        PublicKey::deserialize(&identity_key).map_err(|_| bad(TEXT_INVALID_IDENTITY_KEY))?;
    // Tentýž soukromý klíč má víc zápisů veřejného klíče (horní bit
    // u-souřadnice, přičtený bod malého řádu) a libsignal k nim podpisy
    // ověří. Každý zápis má jiný otisk, takže jen kanonický zápis drží
    // blokaci: jinak by se zablokovaná identita vrátila pod aliasem.
    if !identity.is_canonical() {
        return Err(bad(TEXT_INVALID_IDENTITY_KEY));
    }
    if !identity.verify_signature(&spk_pub, &spk_sig) {
        return Err(bad("podpis signed prekey nesedí"));
    }
    if !identity.verify_signature(&kyber_pub, &kyber_sig) {
        return Err(bad("podpis kyber prekey nesedí"));
    }
    // Důkaz držení klíče u každé registrace: SPK a Kyber jdou z veřejného
    // bundlu opsat, takže bez důkazu by šlo zaregistrovat cizí klíč, obsadit
    // jeho vyřazenou adresu nebo zjistit, zda je identita zablokovaná.
    // Důkaz s otiskem těla platí jen pro tělo, se kterým ho klient podepsal:
    // adresa doručení v těle jinak podpisem krytá není.
    let proven = identity_proof_valid(headers, &identity, "POST /v1/register")
        .is_some_and(|claim| claim.matches(body_sha256));
    if !proven {
        return Err(ApiError::tagged(
            StatusCode::UNAUTHORIZED,
            "chybí nebo neplatí důkaz držení klíče",
            TAG_IDENTITY_PROOF,
        ));
    }
    // Globální strop až tady: požadavek bez platných důkazů do DB nedojde
    // a strop určený k její ochraně nemá vybírat.
    state.register_global.check().map_err(ApiError::too_many)?;
    let fingerprint = Fingerprint::of_identity_key(&identity_key);

    // ThreadRng je !Send — nesmí přežít přes await, proto vlastní scope.
    let (account_id, device_uuid) = {
        let mut rng = rand::rng();
        let mut account_id = vec![0u8; 16];
        rng.fill_bytes(&mut account_id);
        let mut device_uuid = vec![0u8; 16];
        rng.fill_bytes(&mut device_uuid);
        (account_id, device_uuid)
    };

    let mut tx = state.pool.begin().await.map_err(internal)?;
    // Zámek otisku jako první příkaz: blokace téže identity (jiný proces)
    // čeká na commit registrace a najde ji, nebo registrace po jejím commitu
    // uvidí seznam blokací.
    blocking::lock(&mut tx, &fingerprint)
        .await
        .map_err(internal)?;
    if blocking::is_blocked(&mut *tx, &fingerprint)
        .await
        .map_err(internal)?
    {
        tracing::info!("registrace zablokované identity odmítnuta");
        return Err(ApiError::tagged(
            StatusCode::FORBIDDEN,
            blocking::TEXT_BLOCKED,
            TAG_IDENTITY_BLOCKED,
        ));
    }
    #[cfg(test)]
    state
        .test_hooks
        .after_block_check(&mut tx)
        .await
        .map_err(internal)?;

    let inserted = sqlx::query(
        "INSERT INTO identities (account_id, identity_key) VALUES ($1, $2)
         ON CONFLICT (identity_key) DO NOTHING",
    )
    .bind(&account_id)
    .bind(&identity_key)
    .execute(&mut *tx)
    .await
    .map_err(internal)?;
    // Identita už existuje = obnova ze 24 slov na novém telefonu (nebo
    // reinstalace). Důkaz držení klíče je ověřený výše, účet tedy převezme
    // nové zařízení: stará zařízení, jejich prekeys, push tokeny i nedoručená
    // fronta pryč (nové zařízení staré ratchet relace stejně nemá),
    // account_id zůstává — kontakty ho znají. Ostatní adresy se vyřadí.
    let mut replaced = blocking::Removed::default();
    let account_id = if inserted.rows_affected() == 0 {
        #[cfg(test)]
        state.test_hooks.before_takeover_lock.pass().await;
        let existing: Option<Vec<u8>> = sqlx::query_scalar(
            "SELECT account_id FROM identities WHERE identity_key = $1 FOR UPDATE",
        )
        .bind(&identity_key)
        .fetch_optional(&mut *tx)
        .await
        .map_err(internal)?;
        #[cfg(test)]
        state.test_hooks.after_takeover_lock.pass().await;
        // Mezi INSERT a zámkem řádku ji smazat nejde: všechna mazání drží
        // zámek otisku, nebo identitu přeskočí (úklid). Pojistka, kdyby
        // nějaké mazání zámek obešlo: klient to zkusí znovu.
        let Some(existing) = existing else {
            return Err(ApiError::tagged(
                StatusCode::SERVICE_UNAVAILABLE,
                "registrace se právě mění, zkus to znovu",
                TAG_RETRY,
            ));
        };
        replaced = blocking::delete_devices(
            &mut tx,
            &existing,
            &fingerprint,
            Retire::Standard,
            Some(&delivery_address),
        )
        .await
        .map_err(internal)?;
        tracing::info!("identita převzata novým zařízením (obnova)");
        existing
    } else {
        account_id
    };

    match blocking::check_address(
        &mut tx,
        &delivery_address,
        &fingerprint,
        &replaced.addresses,
    )
    .await
    {
        Ok(()) => {}
        Err(AddressError::Taken) => return Err(address_taken()),
        Err(AddressError::Db(e)) => return Err(internal(e)),
    }
    // ON CONFLICT: souběžná registrace jiné identity se stejnou adresou
    // (jiný zámek) dostane 409 místo 500 z unikátního indexu.
    let device_inserted: Option<Vec<u8>> = sqlx::query_scalar(
        "INSERT INTO devices (device_uuid, account_id, device_id, registration_id, delivery_address)
         VALUES ($1, $2, $3, $4, $5)
         ON CONFLICT (delivery_address) DO NOTHING
         RETURNING device_uuid",
    )
    .bind(&device_uuid)
    .bind(&account_id)
    .bind(body.device_id)
    .bind(body.registration_id)
    .bind(&delivery_address)
    .fetch_optional(&mut *tx)
    .await
    .map_err(internal)?;
    if device_inserted.is_none() {
        return Err(address_taken());
    }

    sqlx::query(
        "INSERT INTO signed_prekeys (device_uuid, key_id, public_key, signature)
         VALUES ($1, $2, $3, $4)",
    )
    .bind(&device_uuid)
    .bind(body.signed_prekey.key_id)
    .bind(&spk_pub)
    .bind(&spk_sig)
    .execute(&mut *tx)
    .await
    .map_err(internal)?;

    sqlx::query(
        "INSERT INTO kyber_prekeys (device_uuid, key_id, public_key, signature, is_last_resort)
         VALUES ($1, $2, $3, $4, $5)",
    )
    .bind(&device_uuid)
    .bind(body.kyber_prekey.key_id)
    .bind(&kyber_pub)
    .bind(&kyber_sig)
    .bind(body.kyber_prekey.is_last_resort)
    .execute(&mut *tx)
    .await
    .map_err(internal)?;

    for otp in &body.one_time_prekeys {
        let otp_pub = b64("one_time_prekeys.public_key", &otp.public_key, Some(33))?;
        sqlx::query(
            "INSERT INTO one_time_prekeys (device_uuid, key_id, public_key) VALUES ($1, $2, $3)",
        )
        .bind(&device_uuid)
        .bind(otp.key_id)
        .bind(&otp_pub)
        .execute(&mut *tx)
        .await
        .map_err(internal)?;
    }

    tx.commit().await.map_err(internal)?;
    // Stará zařízení odpojit hned, ne až kontrolou spojení: jinak by po
    // převzetí chvíli poslouchala dvě zařízení na téže adrese.
    state.conns.kick_devices(&replaced.device_uuids, 410);

    Ok((
        StatusCode::CREATED,
        Json(RegisterOut {
            account_id: hex::encode(account_id),
            device_uuid: hex::encode(device_uuid),
        }),
    ))
}

// ── GET /v1/keys/{delivery_address} ───────────────────────────────────

#[derive(Serialize)]
pub struct PreKeyOut {
    pub key_id: i32,
    pub public_key: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub signature: Option<String>,
}

#[derive(Serialize)]
pub struct DeviceBundleOut {
    pub device_id: i32,
    pub registration_id: i32,
    pub identity_key: String,
    pub signed_prekey: PreKeyOut,
    pub kyber_prekey: PreKeyOut,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub one_time_prekey: Option<PreKeyOut>,
}

#[derive(Serialize)]
pub struct BundlesOut {
    pub devices: Vec<DeviceBundleOut>,
}

pub async fn fetch_bundle(
    State(state): State<Arc<AppState>>,
    Path(delivery_address): Path<String>,
) -> ApiResult<Json<BundlesOut>> {
    let address = hex::decode(&delivery_address).map_err(|_| bad("neplatná adresa"))?;

    let account: Option<(Vec<u8>, Vec<u8>)> = sqlx::query_as(
        "SELECT d.account_id, i.identity_key
         FROM devices d JOIN identities i USING (account_id)
         WHERE d.delivery_address = $1",
    )
    .bind(&address)
    .fetch_optional(&state.pool)
    .await
    .map_err(internal)?;
    let Some((account_id, identity_key)) = account else {
        return Err((StatusCode::NOT_FOUND, "adresa neznámá".to_string()).into());
    };

    // Multi-device fanout: bundle pro všechna zařízení identity.
    let devices: Vec<(Vec<u8>, i32, i32)> = sqlx::query_as(
        "SELECT device_uuid, device_id, registration_id FROM devices WHERE account_id = $1",
    )
    .bind(&account_id)
    .fetch_all(&state.pool)
    .await
    .map_err(internal)?;

    let mut out = Vec::with_capacity(devices.len());
    for (device_uuid, device_id, registration_id) in devices {
        let spk: (i32, Vec<u8>, Vec<u8>) = sqlx::query_as(
            "SELECT key_id, public_key, signature FROM signed_prekeys
             WHERE device_uuid = $1 ORDER BY created_at DESC LIMIT 1",
        )
        .bind(&device_uuid)
        .fetch_one(&state.pool)
        .await
        .map_err(internal)?;

        let kyber: (i32, Vec<u8>, Vec<u8>) = sqlx::query_as(
            "SELECT key_id, public_key, signature FROM kyber_prekeys
             WHERE device_uuid = $1 ORDER BY is_last_resort ASC, created_at DESC LIMIT 1",
        )
        .bind(&device_uuid)
        .fetch_one(&state.pool)
        .await
        .map_err(internal)?;

        // Spotřebuj jeden one-time prekey (DELETE ... RETURNING) —
        // ale jen v mezích hodinového stropu na adresu: bundle bez OTP je
        // povolený fallback, vyčerpaná zásoba cizím ne.
        let otp: Option<(i32, Vec<u8>)> = if state.allow_otp_issue(&address) {
            sqlx::query_as(
                "DELETE FROM one_time_prekeys
                 WHERE (device_uuid, key_id) IN (
                     SELECT device_uuid, key_id FROM one_time_prekeys
                     WHERE device_uuid = $1 ORDER BY key_id
                     FOR UPDATE SKIP LOCKED LIMIT 1)
                 RETURNING key_id, public_key",
            )
            .bind(&device_uuid)
            .fetch_optional(&state.pool)
            .await
            .map_err(internal)?
        } else {
            None
        };

        out.push(DeviceBundleOut {
            device_id,
            registration_id,
            identity_key: BASE64_STANDARD.encode(&identity_key),
            signed_prekey: PreKeyOut {
                key_id: spk.0,
                public_key: BASE64_STANDARD.encode(spk.1),
                signature: Some(BASE64_STANDARD.encode(spk.2)),
            },
            kyber_prekey: PreKeyOut {
                key_id: kyber.0,
                public_key: BASE64_STANDARD.encode(kyber.1),
                signature: Some(BASE64_STANDARD.encode(kyber.2)),
            },
            one_time_prekey: otp.map(|(key_id, public_key)| PreKeyOut {
                key_id,
                public_key: BASE64_STANDARD.encode(public_key),
                signature: None,
            }),
        });
    }

    Ok(Json(BundlesOut { devices: out }))
}

// ── Autentizace zařízení (X-Sepot-Auth) ────────────────────────────────

/// Max stáří podepsaného timestampu v X-Sepot-Auth (replay okno).
const AUTH_WINDOW_MS: i64 = 300_000;

pub(crate) struct AuthedDevice {
    pub account_id: Vec<u8>,
    pub identity_key: Vec<u8>,
    pub device_id: i32,
    pub device_uuid: Vec<u8>,
    /// Kdy se identita registrovala: čerstvý účet má nižší kvóty.
    pub registered_at: chrono::DateTime<chrono::Utc>,
    /// K jakému tělu se podpis váže; routa s tělem to musí porovnat.
    pub body_claim: BodyClaim,
}

/// Ověří hlavičku `X-Sepot-Auth: <device_uuid_hex>.<ts_ms>.<sig_b64>`,
/// kde sig = XEdDSA identity klíčem zařízení nad `"<method_path>\n<ts_ms>"`
/// (s `X-Sepot-Body-SHA256` ještě `"\n<otisk hex>"`, viz [`BodyClaim`]).
/// Sdílí ji sender certificate a upload příloh; do logů nejde nic.
/// Zařízení, které v DB není: 403, smazala-li ho blokace, jinak 410
/// (registrace skončila). device_uuid zná jen zařízení samo, takže ani
/// jedna odpověď nikomu jinému nic neprozradí.
pub(crate) async fn authenticate_device(
    state: &AppState,
    headers: &HeaderMap,
    method_path: &str,
) -> Result<AuthedDevice, ApiError> {
    let unauthorized = || ApiError::from((StatusCode::UNAUTHORIZED, "neautorizováno".to_string()));

    let header = headers
        .get("x-sepot-auth")
        .and_then(|v| v.to_str().ok())
        .ok_or_else(unauthorized)?;
    let mut parts = header.splitn(3, '.');
    let (device_hex, ts_str, sig_b64) = (
        parts.next().ok_or_else(unauthorized)?,
        parts.next().ok_or_else(unauthorized)?,
        parts.next().ok_or_else(unauthorized)?,
    );

    let device_uuid = hex::decode(device_hex).map_err(|_| unauthorized())?;
    if device_uuid.len() != 16 {
        return Err(unauthorized());
    }
    let ts: i64 = ts_str.parse().map_err(|_| unauthorized())?;
    let signature = BASE64_STANDARD.decode(sig_b64).map_err(|_| unauthorized())?;

    let now_ms = chrono::Utc::now().timestamp_millis();
    // abs_diff: `(now - ts).abs()` by u extrémního ts v release přetekl.
    if now_ms.abs_diff(ts) > AUTH_WINDOW_MS as u64 {
        return Err(unauthorized());
    }

    let row: Option<(Vec<u8>, Vec<u8>, i32, chrono::DateTime<chrono::Utc>)> = sqlx::query_as(
        "SELECT d.account_id, i.identity_key, d.device_id, i.registered_at
         FROM devices d JOIN identities i USING (account_id)
         WHERE d.device_uuid = $1",
    )
    .bind(&device_uuid)
    .fetch_optional(&state.pool)
    .await
    .map_err(internal)?;
    let Some((account_id, identity_key, device_id, registered_at)) = row else {
        return Err(
            if blocking::blocked_device(&state.pool, &device_uuid)
                .await
                .map_err(internal)?
            {
                ApiError::tagged(
                    StatusCode::FORBIDDEN,
                    blocking::TEXT_BLOCKED,
                    TAG_IDENTITY_BLOCKED,
                )
            } else {
                ApiError::tagged(
                    StatusCode::GONE,
                    blocking::TEXT_DEVICE_GONE,
                    TAG_DEVICE_GONE,
                )
            },
        );
    };

    let body_claim = BodyClaim::from_headers(headers).ok_or_else(unauthorized)?;
    let message = body_claim.message(method_path, ts);
    let identity = PublicKey::deserialize(&identity_key).map_err(|_| unauthorized())?;
    if !identity.verify_signature(message.as_bytes(), &signature) {
        return Err(unauthorized());
    }
    // Registrace zablokované identity vznikne jen obejitím blokace (starší
    // image během návratu). Dorovnání ji smaže až v hodinové údržbě; do té
    // doby nesmí dostat certifikát odesílatele ani nic jiného.
    if blocking::is_blocked(&state.pool, &Fingerprint::of_identity_key(&identity_key))
        .await
        .map_err(internal)?
    {
        return Err(ApiError::tagged(
            StatusCode::FORBIDDEN,
            blocking::TEXT_BLOCKED,
            TAG_IDENTITY_BLOCKED,
        ));
    }

    Ok(AuthedDevice {
        account_id,
        identity_key,
        device_id,
        device_uuid,
        registered_at,
        body_claim,
    })
}

// ── POST /v1/keys ──────────────────────────────────────────────────────

#[derive(Deserialize)]
pub struct UploadKeysIn {
    #[serde(default)]
    pub signed_prekey: Option<PreKeyIn>,
    #[serde(default)]
    pub kyber_prekey: Option<PreKeyIn>,
    #[serde(default)]
    pub one_time_prekeys: Vec<PreKeyIn>,
}

#[derive(Serialize)]
pub struct UploadKeysOut {
    /// Kolik OTP zařízení má po nahrání.
    pub one_time_prekeys: i64,
}


/// Po kolika dnech se starý signed prekey smaže (po rotaci ho relay ještě
/// drží, protože bundle s ním mohl někdo stáhnout těsně před výměnou).
const SIGNED_PREKEY_GRACE_DAYS: i64 = 30;

/// Doplnění one-time prekeys a rotace signed / Kyber prekey. Auth podpis: `"POST /v1/keys\n<ts>"`.
/// Podpisy nových prekeys se ověřují proti identity klíči zařízení.
pub async fn upload_keys(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    HashedJson {
        value: body,
        sha256: body_sha256,
    }: HashedJson<UploadKeysIn>,
) -> ApiResult<Json<UploadKeysOut>> {
    let authed = authenticate_device(&state, &headers, "POST /v1/keys").await?;
    if !authed.body_claim.matches(&body_sha256) {
        return Err((StatusCode::UNAUTHORIZED, TEXT_BODY_MISMATCH.to_string()).into());
    }
    if body.one_time_prekeys.len() > MAX_ONE_TIME_PREKEYS {
        return Err(bad("příliš mnoho one-time prekeys"));
    }
    let identity =
        PublicKey::deserialize(&authed.identity_key).map_err(|_| bad(TEXT_INVALID_IDENTITY_KEY))?;

    let mut tx = state.pool.begin().await.map_err(internal)?;

    if let Some(spk) = &body.signed_prekey {
        let public = b64("signed_prekey.public_key", &spk.public_key, Some(33))?;
        let sig = b64(
            "signed_prekey.signature",
            spk.signature.as_deref().ok_or_else(|| bad("chybí podpis signed prekey"))?,
            Some(64),
        )?;
        if !identity.verify_signature(&public, &sig) {
            return Err(bad("podpis signed prekey nesedí"));
        }
        sqlx::query(
            "INSERT INTO signed_prekeys (device_uuid, key_id, public_key, signature)
             VALUES ($1, $2, $3, $4)
             ON CONFLICT (device_uuid, key_id) DO NOTHING",
        )
        .bind(&authed.device_uuid)
        .bind(spk.key_id)
        .bind(&public)
        .bind(&sig)
        .execute(&mut *tx)
        .await
        .map_err(internal)?;
        // Starší než grace a zároveň ne nejnovější → pryč.
        sqlx::query(
            "DELETE FROM signed_prekeys WHERE device_uuid = $1
               AND created_at < now() - make_interval(days => $2)
               AND key_id <> (SELECT key_id FROM signed_prekeys WHERE device_uuid = $1
                              ORDER BY created_at DESC LIMIT 1)",
        )
        .bind(&authed.device_uuid)
        .bind(SIGNED_PREKEY_GRACE_DAYS as i32)
        .execute(&mut *tx)
        .await
        .map_err(internal)?;
    }

    if let Some(kyber) = &body.kyber_prekey {
        let public = b64("kyber_prekey.public_key", &kyber.public_key, None)?;
        if public.len() > 2048 {
            return Err(bad("kyber prekey je příliš dlouhý"));
        }
        let sig = b64(
            "kyber_prekey.signature",
            kyber.signature.as_deref().ok_or_else(|| bad("chybí podpis kyber prekey"))?,
            Some(64),
        )?;
        if !identity.verify_signature(&public, &sig) {
            return Err(bad("podpis kyber prekey nesedí"));
        }
        sqlx::query(
            "INSERT INTO kyber_prekeys (device_uuid, key_id, public_key, signature, is_last_resort)
             VALUES ($1, $2, $3, $4, $5)
             ON CONFLICT (device_uuid, key_id) DO NOTHING",
        )
        .bind(&authed.device_uuid)
        .bind(kyber.key_id)
        .bind(&public)
        .bind(&sig)
        .bind(kyber.is_last_resort)
        .execute(&mut *tx)
        .await
        .map_err(internal)?;
        sqlx::query(
            "DELETE FROM kyber_prekeys WHERE device_uuid = $1 AND is_last_resort
               AND created_at < now() - make_interval(days => $2)
               AND key_id <> (SELECT key_id FROM kyber_prekeys WHERE device_uuid = $1
                              AND is_last_resort ORDER BY created_at DESC LIMIT 1)",
        )
        .bind(&authed.device_uuid)
        .bind(SIGNED_PREKEY_GRACE_DAYS as i32)
        .execute(&mut *tx)
        .await
        .map_err(internal)?;
    }

    let (mut stored,): (i64,) =
        sqlx::query_as("SELECT count(*) FROM one_time_prekeys WHERE device_uuid = $1")
            .bind(&authed.device_uuid)
            .fetch_one(&mut *tx)
            .await
            .map_err(internal)?;
    for otp in &body.one_time_prekeys {
        // Strop zásoby OTP (`Limits::max_stored_otp`, výchozí 100) — nad něj se
        // další zahodí (klient posílá dávky po 50, jako při registraci sto).
        if stored >= state.limits.max_stored_otp {
            break;
        }
        let public = b64("one_time_prekeys.public_key", &otp.public_key, Some(33))?;
        let res = sqlx::query(
            "INSERT INTO one_time_prekeys (device_uuid, key_id, public_key) VALUES ($1, $2, $3)
             ON CONFLICT (device_uuid, key_id) DO NOTHING",
        )
        .bind(&authed.device_uuid)
        .bind(otp.key_id)
        .bind(&public)
        .execute(&mut *tx)
        .await
        .map_err(internal)?;
        stored += res.rows_affected() as i64;
    }

    tx.commit().await.map_err(internal)?;
    Ok(Json(UploadKeysOut {
        one_time_prekeys: stored,
    }))
}

// ── DELETE /v1/identity ────────────────────────────────────────────────

/// Deregistrace účtu (GDPR čl. 17, store požadavek na smazání účtu).
/// Auth stejným podpisem jako sender certificate — smazat účet smí jen
/// držitel identity klíče. Kaskáda v DB odnese devices → prekeys +
/// push_tokens; fronta zpráv je vázaná na delivery_address bez FK,
/// maže se explicitně v téže transakci. Přílohy vazbu na účet nemají
/// (bearer capability) — dožijí TTL sweep.
pub async fn delete_identity(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
) -> ApiResult<StatusCode> {
    let authed = authenticate_device(&state, &headers, "DELETE /v1/identity").await?;
    let removed = state
        .delete_identity(&authed.account_id)
        .await
        .map_err(internal)?;
    tracing::info!("identita smazána na žádost zařízení");
    // Registrace skončila: spojení smazaných zařízení odpojit hned, další
    // AUTH by stejně dostal 410.
    state.conns.kick_devices(&removed, 410);
    Ok(StatusCode::NO_CONTENT)
}

// ── GET /v1/certificate/delivery ───────────────────────────────────────

#[derive(Serialize)]
pub struct CertificateOut {
    pub sender_certificate: String,
    pub trust_root: String,
    pub sender_uuid: String,
    pub expires_at_ms: u64,
}

pub async fn certificate_delivery(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
) -> ApiResult<Json<CertificateOut>> {
    let authed =
        authenticate_device(&state, &headers, "GET /v1/certificate/delivery").await?;

    let now_ms = chrono::Utc::now().timestamp_millis();
    let sender_uuid = hex::encode(&authed.account_id);
    let (cert, expires_at_ms) = state
        .certs
        .issue(
            &sender_uuid,
            authed.device_id as u32,
            &authed.identity_key,
            now_ms as u64,
        )
        .map_err(internal)?;

    Ok(Json(CertificateOut {
        sender_certificate: BASE64_STANDARD.encode(cert),
        trust_root: BASE64_STANDARD.encode(&state.certs.trust_root_public),
        sender_uuid,
        expires_at_ms,
    }))
}

#[cfg(test)]
mod db_tests {
    //! Registrace, převzetí a autentizace nad reálným Postgresem (testkit).
    //! #[ignore] — spouštět s DB: `cargo test -p sepot-relay -- --ignored`.
    use std::sync::atomic::Ordering;
    use std::time::Duration;

    use super::*;
    use crate::blocking::{addr_hash, owner_tag, BlockOptions};
    use crate::testkit::{self, rand_bytes, TestIdentity};

    async fn identities_with_key(state: &AppState, key: &[u8]) -> i64 {
        testkit::count(
            &state.pool,
            "SELECT count(*) FROM identities WHERE identity_key = $1",
            key,
        )
        .await
    }

    async fn retired(state: &AppState, address: &[u8]) -> i64 {
        testkit::count(
            &state.pool,
            "SELECT count(*) FROM retired_addresses WHERE addr_hash = $1",
            &addr_hash(address),
        )
        .await
    }

    fn assert_error(error: &ApiError, status: StatusCode, tag: Option<&str>) {
        assert_eq!(error.status, status, "{error:?}");
        assert_eq!(error.tag, tag, "{error:?}");
    }

    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn registrace_bez_dukazu_vrati_401() {
        let state = testkit::state().await;
        let identity = TestIdentity::new();
        let impostor = TestIdentity::new();
        let stale_ts = chrono::Utc::now().timestamp_millis() - 2 * AUTH_WINDOW_MS;
        let stale_signature = identity.sign(format!("POST /v1/register\n{stale_ts}").as_bytes());
        let mut stale = HeaderMap::new();
        stale.insert(
            "x-sepot-identity-proof",
            HeaderValue::from_str(&format!(
                "{stale_ts}.{}",
                BASE64_STANDARD.encode(stale_signature)
            ))
            .unwrap(),
        );

        for headers in [HeaderMap::new(), impostor.proof_headers(), stale] {
            let result = register_device(
                &state,
                &headers,
                identity.key.clone(),
                identity.register_body(&rand_bytes(32)),
                &[0; SHA256_LEN],
            )
            .await;
            let Err(error) = result else {
                panic!("bez platného důkazu registrace neprojde");
            };
            assert_error(&error, StatusCode::UNAUTHORIZED, Some(TAG_IDENTITY_PROOF));
        }
        assert_eq!(identities_with_key(&state, &identity.key).await, 0);
    }

    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn registrace_zablokovaneho_klice_vrati_403() {
        let state = testkit::state().await;
        let identity = TestIdentity::new();
        let address = rand_bytes(32);
        blocking::block(&state.pool, &identity.fingerprint, BlockOptions::default())
            .await
            .expect("blokace");

        let error = testkit::register(&state, &identity, &address)
            .await
            .expect_err("zablokovaná identita");
        assert_error(&error, StatusCode::FORBIDDEN, Some(TAG_IDENTITY_BLOCKED));
        assert_eq!(identities_with_key(&state, &identity.key).await, 0);
        let devices = testkit::count(
            &state.pool,
            "SELECT count(*) FROM devices WHERE delivery_address = $1",
            &address,
        )
        .await;
        assert_eq!(devices, 0);
        testkit::forget(&state.pool, &identity, &[&address]).await;
    }

    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn prevzeti_zablokovaneho_klice_vrati_403() {
        let state = testkit::state().await;
        let identity = TestIdentity::new();
        let (address, new_address) = (rand_bytes(32), rand_bytes(32));
        let first = testkit::register(&state, &identity, &address)
            .await
            .expect("registrace");
        // Blokace bez smazání registrace: tak ji převzetí najde po návratu
        // ze starší verze relaye, než proběhne dorovnání.
        sqlx::query(
            "INSERT INTO blocked_identities (fingerprint, expires_on)
             VALUES ($1, current_date + 30)",
        )
        .bind(identity.fingerprint.0)
        .execute(&state.pool)
        .await
        .unwrap();

        let error = testkit::register(&state, &identity, &new_address)
            .await
            .expect_err("převzetí zablokované identity");
        assert_error(&error, StatusCode::FORBIDDEN, Some(TAG_IDENTITY_BLOCKED));
        let devices = testkit::count(
            &state.pool,
            "SELECT count(*) FROM devices WHERE device_uuid = $1",
            &first.device_uuid,
        )
        .await;
        assert_eq!(devices, 1, "zařízení zůstávají");
        testkit::forget(&state.pool, &identity, &[&address, &new_address]).await;
    }

    /// Bez zámku otisku v registraci padá: blokace se vejde mezi kontrolu
    /// blokace a zápis identity (háček tam spí 50 ms) a registrace pak
    /// přežije.
    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn soubeh_blokace_a_registrace() {
        const ROUNDS: usize = 200;
        const WAVE: usize = 10;
        /// Blokace startuje, až registrace spí v háčku.
        const BLOCK_DELAY: Duration = Duration::from_millis(10);

        let pool = testkit::shared_pool(2 * WAVE as u32 + 2).await;
        let state = Arc::new(testkit::state_with_pool(pool).await);
        state
            .test_hooks
            .sleep_after_block_check
            .store(true, Ordering::Relaxed);

        let mut registered_first = 0;
        for _ in 0..ROUNDS / WAVE {
            let mut rounds = Vec::new();
            for _ in 0..WAVE {
                let identity = Arc::new(TestIdentity::new());
                let address = rand_bytes(32);
                let registration = {
                    let (state, identity, address) =
                        (state.clone(), identity.clone(), address.clone());
                    tokio::spawn(
                        async move { testkit::register(&state, &identity, &address).await },
                    )
                };
                let block = {
                    let (state, identity) = (state.clone(), identity.clone());
                    tokio::spawn(async move {
                        tokio::time::sleep(BLOCK_DELAY).await;
                        blocking::block(&state.pool, &identity.fingerprint, BlockOptions::default())
                            .await
                    })
                };
                rounds.push((identity, address, registration, block));
            }
            for (identity, address, registration, block) in rounds {
                let registration = registration.await.unwrap();
                block.await.unwrap().expect("blokace");
                match registration {
                    Ok(_) => registered_first += 1,
                    Err(error) => {
                        assert_error(&error, StatusCode::FORBIDDEN, Some(TAG_IDENTITY_BLOCKED))
                    }
                }
                assert_eq!(
                    identities_with_key(&state, &identity.key).await,
                    0,
                    "registrace zablokovaného otisku přežila"
                );
                testkit::forget(&state.pool, &identity, &[&address]).await;
            }
        }
        assert!(
            registered_first > 0,
            "souběh nenastal: blokace vždy předběhla registraci"
        );
    }

    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn adresa_ziveho_zarizeni_vrati_409() {
        let state = testkit::state().await;
        let (owner, intruder) = (TestIdentity::new(), TestIdentity::new());
        let address = rand_bytes(32);
        testkit::register(&state, &owner, &address)
            .await
            .expect("registrace");

        let error = testkit::register(&state, &intruder, &address)
            .await
            .expect_err("adresa je obsazená");
        assert_error(&error, StatusCode::CONFLICT, Some(TAG_ADDRESS_TAKEN));
        assert_eq!(identities_with_key(&state, &intruder.key).await, 0);
        testkit::forget(&state.pool, &owner, &[&address]).await;
    }

    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn vyrazena_adresa_jine_identity_vrati_409() {
        let state = testkit::state().await;
        let (owner, intruder) = (TestIdentity::new(), TestIdentity::new());
        let address = rand_bytes(32);
        let registered = testkit::register(&state, &owner, &address)
            .await
            .expect("registrace");
        state
            .delete_identity(&registered.account_id)
            .await
            .expect("smazání účtu");
        assert_eq!(retired(&state, &address).await, 1);

        let error = testkit::register(&state, &intruder, &address)
            .await
            .expect_err("vyřazená adresa cizí identity");
        assert_error(&error, StatusCode::CONFLICT, Some(TAG_ADDRESS_TAKEN));
        assert_eq!(retired(&state, &address).await, 1, "výluka trvá");
        testkit::forget(&state.pool, &owner, &[&address]).await;
    }

    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn vyrazena_adresa_stejne_identity_se_vrati() {
        let state = testkit::state().await;
        let owner = TestIdentity::new();
        let address = rand_bytes(32);
        let registered = testkit::register(&state, &owner, &address)
            .await
            .expect("registrace");
        state
            .delete_identity(&registered.account_id)
            .await
            .expect("smazání účtu");

        testkit::register(&state, &owner, &address)
            .await
            .expect("vlastník si adresu vezme zpět");
        assert_eq!(retired(&state, &address).await, 0, "řádek výluky smazán");
        testkit::forget(&state.pool, &owner, &[&address]).await;
    }

    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn smazani_uctu_vyradi_adresy_na_rok() {
        let state = Arc::new(testkit::state().await);
        let owner = TestIdentity::new();
        let address = rand_bytes(32);
        let registered = testkit::register(&state, &owner, &address)
            .await
            .expect("registrace");

        let headers = owner.auth_headers(&registered.device_uuid, "DELETE /v1/identity");
        let status = delete_identity(State(state.clone()), headers)
            .await
            .expect("smazání účtu");
        assert_eq!(status, StatusCode::NO_CONTENT);

        let hash = addr_hash(&address);
        let (year, tag): (bool, [u8; 32]) = sqlx::query_as(
            "SELECT expires_on = current_date + $2, owner_tag
               FROM retired_addresses WHERE addr_hash = $1",
        )
        .bind(hash)
        .bind(blocking::RETIRED_ADDRESS_DAYS)
        .fetch_one(&state.pool)
        .await
        .expect("adresa vyřazená");
        assert!(year, "výluka na rok");
        assert_eq!(tag, owner_tag(&hash, &owner.fingerprint));
        testkit::forget(&state.pool, &owner, &[&address]).await;
    }

    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn prevzeti_vyradi_stare_adresy_krome_nove() {
        let state = testkit::state().await;
        let owner = TestIdentity::new();
        let (kept, other) = (rand_bytes(32), rand_bytes(32));
        let first = testkit::register(&state, &owner, &kept)
            .await
            .expect("registrace");
        // Druhé zařízení téže identity s vlastní adresou.
        sqlx::query(
            "INSERT INTO devices (device_uuid, account_id, device_id, registration_id, delivery_address)
             VALUES ($1, $2, 2, 2, $3)",
        )
        .bind(rand_bytes(16))
        .bind(&first.account_id)
        .bind(&other)
        .execute(&state.pool)
        .await
        .unwrap();

        let again = testkit::register(&state, &owner, &kept)
            .await
            .expect("převzetí stejnou adresou");
        assert_eq!(again.account_id, first.account_id, "account_id zůstává");
        assert_eq!(retired(&state, &kept).await, 0, "nová adresa se nevyřazuje");
        assert_eq!(retired(&state, &other).await, 1, "ostatní adresy ano");
        let addresses: Vec<Vec<u8>> =
            sqlx::query_scalar("SELECT delivery_address FROM devices WHERE account_id = $1")
                .bind(&first.account_id)
                .fetch_all(&state.pool)
                .await
                .unwrap();
        assert_eq!(addresses, vec![kept.clone()]);
        testkit::forget(&state.pool, &owner, &[&kept, &other]).await;
    }

    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn authenticate_device_vraci_403_410_401() {
        let state = testkit::state().await;
        let path = "GET /v1/certificate/delivery";
        let rejection = |result: Result<AuthedDevice, ApiError>| match result {
            Ok(_) => panic!("autentizace neměla projít"),
            Err(error) => error,
        };

        let blocked = TestIdentity::new();
        let blocked_address = rand_bytes(32);
        let device = testkit::register(&state, &blocked, &blocked_address)
            .await
            .expect("registrace")
            .device_uuid;
        blocking::block(&state.pool, &blocked.fingerprint, BlockOptions::default())
            .await
            .expect("blokace");
        let error = rejection(
            authenticate_device(&state, &blocked.auth_headers(&device, path), path).await,
        );
        assert_error(&error, StatusCode::FORBIDDEN, Some(TAG_IDENTITY_BLOCKED));

        let unknown = TestIdentity::new();
        let error = rejection(
            authenticate_device(&state, &unknown.auth_headers(&rand_bytes(16), path), path).await,
        );
        assert_error(&error, StatusCode::GONE, Some(TAG_DEVICE_GONE));

        let owner = TestIdentity::new();
        let owner_address = rand_bytes(32);
        let device = testkit::register(&state, &owner, &owner_address)
            .await
            .expect("registrace")
            .device_uuid;
        let impostor = TestIdentity::new();
        let error = rejection(
            authenticate_device(&state, &impostor.auth_headers(&device, path), path).await,
        );
        assert_error(&error, StatusCode::UNAUTHORIZED, None);
        assert!(
            authenticate_device(&state, &owner.auth_headers(&device, path), path)
                .await
                .is_ok(),
            "vlastník projde"
        );

        testkit::forget(&state.pool, &blocked, &[&blocked_address]).await;
        testkit::forget(&state.pool, &owner, &[&owner_address]).await;
    }

    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn server_info_hlasi_blokaci_a_lhutu() {
        let Json(info) = server_info(State(Arc::new(testkit::state().await))).await;
        let capabilities = info["capabilities"].as_array().expect("capabilities");
        assert!(capabilities.iter().any(|c| c == "identity-block"), "{info}");
        assert!(info["inactive_registration_days"].is_null(), "{info}");

        let mut state = testkit::state().await;
        state.limits.inactive_cleanup = true;
        let Json(info) = server_info(State(Arc::new(state))).await;
        assert_eq!(
            info["inactive_registration_days"],
            serde_json::json!(crate::cleanup::INACTIVE_REGISTRATION_DAYS)
        );
    }

    /// Podepíše zprávu tak, aby podpis sedl k aliasu klíče.
    type AliasSigner = Box<dyn Fn(&[u8]) -> Vec<u8>>;

    /// Zápis téhož klíče, který libsignal přijme a podpisy k němu ověří,
    /// s jiným otiskem než původní klíč.
    struct KeyAlias {
        family: &'static str,
        key: Vec<u8>,
        sign: AliasSigner,
    }

    /// Horní bit posledního bajtu: dekódování u-souřadnice ho maskuje,
    /// podpis původním klíčem tedy sedí beze změny.
    fn high_bit_alias(identity: &TestIdentity) -> KeyAlias {
        let mut key = identity.key.clone();
        key[32] |= 0x80;
        let keys = identity.keys;
        KeyAlias {
            family: "horní bit",
            key,
            sign: Box::new(move |message| {
                keys.private_key
                    .calculate_signature(message, &mut rand::rng())
                    .expect("podpis")
                    .to_vec()
            }),
        }
    }

    /// Veřejný bod + bod řádu 8; horní bit zůstává čistý. libsignal ověřuje
    /// XEdDSA bez kofaktoru, podpis k aliasu tedy projde, když h ≡ 0 (mod 8):
    /// podepisovač zkouší náhodná r, v průměru osmkrát.
    fn torsion_alias(identity: &TestIdentity) -> KeyAlias {
        use curve25519_dalek::constants::ED25519_BASEPOINT_TABLE;
        use curve25519_dalek::edwards::CompressedEdwardsY;
        use curve25519_dalek::scalar::Scalar;
        use sha2::{Digest, Sha512};

        /// Bod řádu 8 (seznam bodů malého řádu z libsodium).
        const ORDER_8_POINT: &str =
            "26e8958fc2b227b045c3f489f2ef98f0d5dfac05d3c63339b13802886d53fc05";
        /// Pravděpodobnost neúspěchu jednoho pokusu je 7/8; tolik pokusů
        /// selže jen s pravděpodobností pod 10^-14.
        const MAX_ATTEMPTS: usize = 256;

        let torsion = CompressedEdwardsY(
            hex::decode(ORDER_8_POINT)
                .expect("hex")
                .try_into()
                .expect("32 B"),
        )
        .decompress()
        .expect("bod");
        let secret: [u8; 32] = identity
            .keys
            .private_key
            .serialize()
            .try_into()
            .expect("32 B");
        let scalar = Scalar::from_bytes_mod_order(secret);
        let public_point = &scalar * ED25519_BASEPOINT_TABLE;
        assert_eq!(
            &public_point.to_montgomery().to_bytes()[..],
            &identity.key[1..],
            "veřejný klíč = a·B"
        );
        let alias_point = public_point + torsion;
        let mut key = vec![0x05];
        key.extend_from_slice(&alias_point.to_montgomery().to_bytes());
        let parsed = PublicKey::deserialize(&key).expect("libsignal alias přijme");
        let compressed = alias_point.compress();
        let sign_bit = compressed.as_bytes()[31] & 0x80;
        KeyAlias {
            family: "torzní bod",
            key,
            sign: Box::new(move |message| {
                for _ in 0..MAX_ATTEMPTS {
                    let mut wide = [0u8; 64];
                    rand::rng().fill_bytes(&mut wide);
                    let r = Scalar::from_bytes_mod_order_wide(&wide);
                    let r_point = (&r * ED25519_BASEPOINT_TABLE).compress();
                    let digest: [u8; 64] = Sha512::new()
                        .chain_update(r_point.as_bytes())
                        .chain_update(compressed.as_bytes())
                        .chain_update(message)
                        .finalize()
                        .into();
                    let s = Scalar::from_bytes_mod_order_wide(&digest) * scalar + r;
                    let mut signature = [0u8; 64];
                    signature[..32].copy_from_slice(r_point.as_bytes());
                    signature[32..].copy_from_slice(s.as_bytes());
                    signature[63] = (signature[63] & 0x7f) | sign_bit;
                    if parsed.verify_signature(message, &signature) {
                        return signature.to_vec();
                    }
                }
                panic!("podpis k aliasu neprošel ani na {MAX_ATTEMPTS} pokusů");
            }),
        }
    }

    /// Globální strop registrací nevybere požadavek bez platného důkazu
    /// držení klíče; vybere ho až registrace, která jde do DB.
    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn globalni_strop_berou_jen_overene_registrace() {
        /// Jedna registrace za hodinu: druhá ověřená už neprojde.
        const ONE_PER_HOUR: crate::limits::Rate = crate::limits::Rate::new(1, 3_600_000);
        /// Nejméně tolik sekund v Retry-After při hodinové periodě.
        const RETRY_AFTER_FLOOR_SECS: u64 = 3000;
        let mut state = testkit::state().await;
        state.register_global = crate::limits::GlobalLimit::new(Some(ONE_PER_HOUR));
        let (first, second) = (TestIdentity::new(), TestIdentity::new());
        let (first_address, second_address) = (rand_bytes(32), rand_bytes(32));

        for _ in 0..3 {
            let unproven = register_device(
                &state,
                &HeaderMap::new(),
                first.key.clone(),
                first.register_body(&first_address),
                &[0; SHA256_LEN],
            )
            .await
            .err()
            .expect("bez důkazu držení klíče");
            assert_eq!(unproven.status, StatusCode::UNAUTHORIZED);
        }
        testkit::register(&state, &first, &first_address)
            .await
            .expect("neověřené požadavky strop nevybraly");

        let refused = testkit::register(&state, &second, &second_address)
            .await
            .expect_err("strop vybrala první registrace");
        assert_eq!(refused.status, StatusCode::TOO_MANY_REQUESTS);
        let response = refused.into_response();
        let retry_after: u64 = response.headers()[header::RETRY_AFTER]
            .to_str()
            .expect("hlavička")
            .parse()
            .expect("sekundy");
        assert!(retry_after > RETRY_AFTER_FLOOR_SECS, "Retry-After odpovídá periodě");

        testkit::forget(&state.pool, &first, &[&first_address]).await;
    }

    /// Podpis s otiskem těla nejde použít s jiným tělem ani bez hlavičky;
    /// podpis bez otisku (klienti do 1.2.7) platí dál.
    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn podpis_s_otiskem_tela_plati_jen_pro_to_telo() {
        let state = testkit::state().await;
        let path = "POST /v1/keys";
        let owner = TestIdentity::new();
        let address = rand_bytes(32);
        let device = testkit::register(&state, &owner, &address)
            .await
            .expect("registrace")
            .device_uuid;
        let (signed_body, other_body) = ([0x11; SHA256_LEN], [0x22; SHA256_LEN]);

        let bound = owner.auth_headers_for_body(&device, path, &signed_body);
        let authed = authenticate_device(&state, &bound, path)
            .await
            .expect("podpis s otiskem");
        assert!(authed.body_claim.matches(&signed_body));
        assert!(!authed.body_claim.matches(&other_body), "jiné tělo");

        let mut stripped = bound.clone();
        stripped.remove(BODY_HASH_HEADER);
        let mut swapped = bound.clone();
        swapped.insert(
            BODY_HASH_HEADER,
            HeaderValue::from_str(&hex::encode(other_body)).unwrap(),
        );
        let mut garbled = bound.clone();
        garbled.insert(BODY_HASH_HEADER, HeaderValue::from_static("abc"));
        for (tampered, why) in [
            (stripped, "hlavička vypuštěná"),
            (swapped, "otisk vyměněný"),
            (garbled, "otisk není otisk"),
        ] {
            let error = authenticate_device(&state, &tampered, path)
                .await
                .err()
                .expect(why);
            assert_eq!(error.status, StatusCode::UNAUTHORIZED, "{why}");
        }

        let legacy = authenticate_device(&state, &owner.auth_headers(&device, path), path)
            .await
            .expect("podpis bez otisku");
        assert!(legacy.body_claim.matches(&other_body), "bez závazku sedí každé tělo");

        testkit::forget(&state.pool, &owner, &[&address]).await;
    }

    /// Důkaz držení klíče s otiskem těla nepustí registraci s jiným tělem
    /// (podvržená adresa doručení).
    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn registrace_s_otiskem_tela_odmitne_jine_telo() {
        let state = testkit::state().await;
        let identity = TestIdentity::new();
        let address = rand_bytes(32);
        let (signed_body, other_body) = ([0x11; SHA256_LEN], [0x22; SHA256_LEN]);
        let headers = identity.proof_headers_for_body(&signed_body);

        let refused = register_device(
            &state,
            &headers,
            identity.key.clone(),
            identity.register_body(&address),
            &other_body,
        )
        .await
        .err()
        .expect("tělo nesedí k podpisu");
        assert_error(&refused, StatusCode::UNAUTHORIZED, Some(TAG_IDENTITY_PROOF));

        register_device(
            &state,
            &headers,
            identity.key.clone(),
            identity.register_body(&address),
            &signed_body,
        )
        .await
        .map(|_| ())
        .expect("tělo sedí k podpisu");
        testkit::forget(&state.pool, &identity, &[&address]).await;
    }

    /// Extraktor vrací otisk bajtů, jak přišly, a odmítá jako `Json`.
    #[tokio::test]
    async fn hashed_json_vraci_otisk_tela() {
        const RAW: &str = r#"{ "a": 1 }"#;
        let request = |content_type: &str, body: &'static str| {
            Request::builder()
                .method("POST")
                .header(header::CONTENT_TYPE, content_type)
                .body(Body::from(body))
                .expect("požadavek")
        };
        let parsed = HashedJson::<serde_json::Value>::from_request(
            request("application/json", RAW),
            &(),
        )
        .await
        .ok()
        .expect("platné tělo");
        assert_eq!(parsed.value["a"], 1);
        assert_eq!(parsed.sha256.as_slice(), Sha256::digest(RAW).as_slice());

        for (content_type, body, status) in [
            ("text/plain", RAW, StatusCode::UNSUPPORTED_MEDIA_TYPE),
            ("application/json", "{", StatusCode::BAD_REQUEST),
        ] {
            let rejected = HashedJson::<serde_json::Value>::from_request(
                request(content_type, body),
                &(),
            )
            .await
            .err()
            .expect("odmítnutí");
            assert_eq!(rejected.status(), status, "{content_type} {body}");
        }
    }

    /// Sonda DB se mezi dotazy na `/v1/ready` sdílí: druhý dotaz v době
    /// platnosti do databáze nejde.
    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn ready_sdili_vysledek_sondy() {
        let unreachable = sqlx::postgres::PgPoolOptions::new()
            .acquire_timeout(std::time::Duration::from_millis(200))
            .connect_lazy("postgres://127.0.0.1:1/nic")
            .expect("líný pool");
        assert!(!ReadyProbe::default().check(&unreachable).await, "DB neodpovídá");

        let probe = ReadyProbe::default();
        assert!(probe.check(&testkit::shared_pool(1).await).await);
        assert!(
            probe.check(&unreachable).await,
            "platný výsledek se vrací bez dotazu do DB"
        );
    }

    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn nekanonicky_zapis_klice_neobejde_blokaci() {
        let state = testkit::state().await;
        let identity = TestIdentity::new();
        let address = rand_bytes(32);
        testkit::register(&state, &identity, &address)
            .await
            .expect("registrace");
        blocking::block(&state.pool, &identity.fingerprint, BlockOptions::default())
            .await
            .expect("blokace");

        for alias in [high_bit_alias(&identity), torsion_alias(&identity)] {
            let family = alias.family;
            let parsed = PublicKey::deserialize(&alias.key).expect("libsignal alias přijme");
            assert!(!parsed.is_canonical(), "{family}");
            assert_ne!(
                Fingerprint::of_identity_key(&alias.key),
                identity.fingerprint,
                "{family}: jiný otisk"
            );

            // Tělo i důkaz podepsané k aliasu: bez kontroly kanoničnosti
            // by registrace prošla (201).
            let mut body = identity.register_body(&rand_bytes(32));
            body.identity_key = BASE64_STANDARD.encode(&alias.key);
            for prekey in [&mut body.signed_prekey, &mut body.kyber_prekey] {
                let public_key = BASE64_STANDARD.decode(&prekey.public_key).unwrap();
                let signature = (alias.sign)(&public_key);
                assert!(parsed.verify_signature(&public_key, &signature), "{family}");
                prekey.signature = Some(BASE64_STANDARD.encode(signature));
            }
            let ts = chrono::Utc::now().timestamp_millis();
            let proof = (alias.sign)(format!("POST /v1/register\n{ts}").as_bytes());
            let mut headers = HeaderMap::new();
            headers.insert(
                "x-sepot-identity-proof",
                HeaderValue::from_str(&format!("{ts}.{}", BASE64_STANDARD.encode(proof))).unwrap(),
            );

            let result =
                register_device(&state, &headers, alias.key.clone(), body, &[0; SHA256_LEN]).await;
            let Err(error) = result else {
                sqlx::query("DELETE FROM identities WHERE identity_key = $1")
                    .bind(&alias.key)
                    .execute(&state.pool)
                    .await
                    .unwrap();
                panic!("{family}: alias zablokovaného klíče se zaregistroval");
            };
            assert_error(&error, StatusCode::BAD_REQUEST, None);
            assert_eq!(error.message, TEXT_INVALID_IDENTITY_KEY, "{family}");
            assert_eq!(identities_with_key(&state, &alias.key).await, 0, "{family}");
        }

        testkit::forget(&state.pool, &identity, &[&address]).await;
    }

    /// Registrace zablokované identity (vzniklá obejitím blokace, třeba na
    /// starém image) nesmí do dorovnání dostat certifikát odesílatele.
    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn zablokovana_registrace_nedostane_certifikat() {
        let state = Arc::new(testkit::state().await);
        let identity = TestIdentity::new();
        let address = rand_bytes(32);
        let registered = testkit::register(&state, &identity, &address)
            .await
            .expect("registrace");
        sqlx::query(
            "INSERT INTO blocked_identities (fingerprint, expires_on) VALUES ($1, current_date + 30)",
        )
        .bind(identity.fingerprint.0)
        .execute(&state.pool)
        .await
        .unwrap();

        let path = "GET /v1/certificate/delivery";
        let headers = identity.auth_headers(&registered.device_uuid, path);
        let Err(error) = certificate_delivery(State(state.clone()), headers).await else {
            panic!("zablokovaná identita dostala certifikát");
        };
        assert_error(&error, StatusCode::FORBIDDEN, Some(TAG_IDENTITY_BLOCKED));

        testkit::forget(&state.pool, &identity, &[&address]).await;
    }
}
