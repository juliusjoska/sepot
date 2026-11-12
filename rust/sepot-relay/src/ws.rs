//! WS relay kanál: AUTH → CHALLENGE → AUTH_PROOF,
//! pak ENVELOPE/ACK od klienta a RECEIPT/DELIVER od serveru.
//! Logy záměrně bez identifikátorů zařízení a bez IP.
//!
//! Anti-abuse (minimální sada):
//! - cap souběžných spojení per IP (flood ochranu doplňuje CrowdSec na edgi)
//! - deadline na AUTH — neautentizované spojení se po pár sekundách zavře
//! - max velikost WS zprávy těsně nad MAX_ENVELOPE_PAYLOAD
//! - rate limit rámců per spojení (token okno) — přetečení = disconnect

use std::net::{IpAddr, SocketAddr};
use std::sync::Arc;
use std::time::Duration;

use axum::body::Bytes;
use axum::extract::ws::{Message as WsMessage, WebSocket, WebSocketUpgrade};
use axum::extract::{ConnectInfo, State};
use axum::http::{HeaderMap, StatusCode};
use axum::response::IntoResponse;
use chrono::{DateTime, Utc};
use futures_util::{Sink, SinkExt, Stream, StreamExt};
use libsignal_protocol::PublicKey;
use prost::Message;
use rand::RngCore;
use sepot_proto::{v1, AUTH_CONTEXT, MAX_ENVELOPE_PAYLOAD};
use tokio::sync::oneshot;
use tokio::time::Instant;

use crate::blocking;
use crate::fingerprint::Fingerprint;
use crate::outbox::{self, Outbox};
use crate::state::AppState;

/// Neautentizované spojení zavřít po tomto čase od navázání — absolutně,
/// ne „od posledního rámce": Pong rámce před AUTH by jinak držely spojení
/// bez konce.
const AUTH_DEADLINE: Duration = Duration::from_secs(10);
/// Kolik AUTH pokusů smí jedno spojení udělat (každý = dotaz do DB).
const MAX_AUTH_ATTEMPTS: u32 = 3;
/// Rate limit rámců od klienta: max `Limits::ws_frames_per_window` za FRAME_WINDOW.
/// Počítají se jen rámce, které něco stojí (obálka, push registrace, TURN);
/// ACK a Pong ne — klient po vylití velké fronty posílá ACK + doručenku na
/// každou obálku a 429 by ho odpojilo uprostřed, fronta by se po osmi
/// kolech smazala (ztráta zpráv bez útočníka).
const FRAME_WINDOW: Duration = Duration::from_secs(10);
/// Buffery jednoho spojení. Výchozí v axum (tungstenite) jsou 128 KiB čtecí
/// + 128 KiB zapisovací = ~137 KiB RAM na spojení; při 512 MiB stropu
/// kontejneru OOM kolem 3,7–7 tisíc připojených (změřeno). 4 KiB čtecí buffer
/// a zápis bez bufferu (každý rámec se hned flushne) = ~16,6 KiB na spojení,
/// 8 990 spojení = 149 MiB. Velké obálky (256 KiB) tím netrpí: čtecí buffer
/// je jen blok, zprávu skládá tungstenite zvlášť do `max_message_size`.
const WS_READ_BUFFER: usize = 4096;
const WS_WRITE_BUFFER: usize = 0;
/// Push endpoint (URL distributora / FCM token) a VoIP token mají rozumný
/// strop; APNs token je 64 hex, FCM do ~200 znaků, UnifiedPush URL < 1 KiB.
const MAX_PUSH_ENDPOINT_BYTES: usize = 2048;
const MAX_VOIP_TOKEN_BYTES: usize = 256;
/// Pod tímhle počtem one-time prekeys relay po AUTH pošle PrekeysLow.
pub const PREKEYS_LOW_THRESHOLD: i64 = 20;
/// Jak často server posílá WS Ping autentizovanému klientovi.
///
/// Mobilní NAT zahazuje nečinné TCP tiše — bez keepalive se ani jedna strana
/// nedozví, že spojení je mrtvé: klient hlásí „připojeno" a píše do prázdna,
/// relay drží záznam v `online` a proto ani nepošle push budíček. Ping je
/// PROTOKOLOVÝ (ne `v1::Ping`), protože na ten dart:io odpovídá Pongem sám —
/// funguje tedy i s klienty, které jsou už venku a aplikační Ping neznají.
const PING_INTERVAL: Duration = Duration::from_secs(30);
/// Bez jediného rámce od klienta (stačí Pong) je spojení mrtvé. Tři zmeškané
/// pingy — velkoryse, ať krátký výpadek mobilní sítě spojení nezabije.
const IDLE_TIMEOUT: Duration = Duration::from_secs(95);
/// Jak dlouho po konci smyčky smí writer dočerpat rámce a poslat Close.
/// Bez čekání by `abort()` mohl zahodit poslední chybový rámec (403/410)
/// a appka by se nedozvěděla, proč spojení skončilo.
const WRITER_DRAIN: Duration = Duration::from_secs(2);
/// Jak dlouho smí trvat zápis jednoho rámce do socketu. Klient, který na
/// pingy odpovídá, ale ze socketu nečte, by jinak držel plnou frontu
/// spojení bez konce (idle timeout ho nevidí, Pong posílat umí). Minuta
/// stačí i na největší rámec po velmi pomalé lince (256 KiB ≈ 4,4 KiB/s,
/// a část spolkne buffer jádra); kratší lhůta by pomalého klienta odpojila
/// uprostřed rámce a po přihlášení by dostal tentýž rámec znovu.
const WRITE_TIMEOUT: Duration = Duration::from_secs(60);
const TEXT_UNAVAILABLE: &str = "server je dočasně nedostupný";

/// Drop-guard: úbytek čítače spojení i při panice/cancelu handleru.
struct ConnGuard {
    state: Arc<AppState>,
    ip: IpAddr,
}

impl Drop for ConnGuard {
    fn drop(&mut self) {
        self.state.ws_conns.remove_if_mut(&self.ip, |_, n| {
            *n -= 1;
            *n == 0
        });
    }
}

pub async fn ws_handler(
    State(state): State<Arc<AppState>>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    ws: WebSocketUpgrade,
) -> impl IntoResponse {
    // Klíč, ne celá adresa: IPv6 klient by jinak strop spojení obešel
    // další adresou ze své sítě.
    let ip = state.trusted_proxies.client_key(peer.ip(), &headers);
    // Všichni onion klienti mají IP kontejneru Toru → vlastní, vyšší strop.
    let cap = if state.trusted_proxies.is_tor(peer.ip()) {
        state.limits.max_conns_tor
    } else {
        state.limits.max_conns_per_ip
    };

    let over_cap = {
        let mut entry = state.ws_conns.entry(ip).or_insert(0);
        if *entry >= cap {
            true
        } else {
            *entry += 1;
            false
        }
    };
    if over_cap {
        // Log bez IP — jen fakt, že cap zafungoval
        tracing::debug!("ws spojení odmítnuto (cap per IP)");
        return StatusCode::TOO_MANY_REQUESTS.into_response();
    }
    let guard = ConnGuard {
        state: state.clone(),
        ip,
    };

    ws.read_buffer_size(WS_READ_BUFFER)
        .write_buffer_size(WS_WRITE_BUFFER)
        .max_message_size(MAX_ENVELOPE_PAYLOAD + 4096)
        .max_frame_size(MAX_ENVELOPE_PAYLOAD + 4096)
        .on_upgrade(move |socket| async move {
            let _guard = guard;
            handle(state, socket).await;
        })
        .into_response()
}

/// Stav mezi AUTH a AUTH_PROOF.
struct Pending {
    nonce_client: Vec<u8>,
    nonce_server: Vec<u8>,
    delivery_address: Vec<u8>,
    identity_key: Vec<u8>,
    device_uuid: Vec<u8>,
    account_id: Vec<u8>,
    registered_at: DateTime<Utc>,
}

/// Ověřený účet spojení: klíč kvót odesílatele (jen v paměti).
struct Account {
    id: Vec<u8>,
    registered_at: DateTime<Utc>,
}

/// APNs i VoIP token (prázdný = neposlán) musí být hex: jdou do cesty URL
/// požadavku na APNs. Appka je posílá jako hex text.
fn apns_tokens_valid(endpoint: &[u8], voip_token: &[u8]) -> bool {
    [endpoint, voip_token]
        .into_iter()
        .filter(|token| !token.is_empty())
        .all(|token| std::str::from_utf8(token).is_ok_and(crate::apns::valid_device_token))
}

fn server_frame(frame: v1::server_frame::Frame) -> v1::ServerFrame {
    v1::ServerFrame { frame: Some(frame) }
}

fn error_frame(code: u32, message: &str) -> v1::ServerFrame {
    server_frame(v1::server_frame::Frame::Error(v1::Error {
        code,
        message: message.into(),
    }))
}

/// Text chybového rámce, kterým relay odpojuje ověřené spojení.
fn rejection_text(code: u32) -> &'static str {
    match code {
        403 => blocking::TEXT_BLOCKED,
        410 => blocking::TEXT_DEVICE_GONE,
        _ => TEXT_UNAVAILABLE,
    }
}

/// Zařízení v DB není: smazala ho blokace (403), nebo smazání účtu,
/// převzetí či úklid (410). Chyba DB při rozlišení = 503.
async fn missing_device_frame(state: &AppState, device_uuid: &[u8]) -> v1::ServerFrame {
    match blocking::blocked_device(&state.pool, device_uuid).await {
        Ok(true) => error_frame(403, blocking::TEXT_BLOCKED),
        Ok(false) => error_frame(410, blocking::TEXT_DEVICE_GONE),
        Err(e) => {
            tracing::warn!("AUTH: dotaz na blokaci selhal: {e}");
            error_frame(503, TEXT_UNAVAILABLE)
        }
    }
}

/// Výsledek zařazení rámce do fronty spojení z hlavní smyčky.
enum Pushed {
    Sent,
    /// Relay mezitím rozhodl spojení odpojit tímto kódem.
    Kicked(u32),
    /// Writer skončil, spojení je mrtvé.
    Closed,
}

/// Zařadí rámec do fronty spojení. Na místo čeká (doručenku zahodit nejde,
/// klient by obálku poslal znovu), ale čekání přeruší odpojení i konec
/// writeru: smyčka zaseknutá o nečtoucího klienta by jinak neviděla kick
/// a spojení by zůstalo v `online`.
async fn push(
    outbox: &Outbox,
    kick: &mut Option<oneshot::Receiver<u32>>,
    frame: v1::ServerFrame,
) -> Pushed {
    tokio::select! {
        biased;
        code = kicked(kick) => Pushed::Kicked(code),
        sent = outbox.send(&frame) => match sent {
            Ok(()) => Pushed::Sent,
            Err(outbox::Closed) => Pushed::Closed,
        },
    }
}

/// Práce po přihlášení (vylití fronty, hint na prekeys) běží vedle hlavní
/// smyčky. Doběhne s úlohou; bez úlohy nikdy.
type AfterAuth = std::pin::Pin<Box<dyn std::future::Future<Output = ()> + Send>>;

async fn finished(slot: &mut Option<AfterAuth>) {
    match slot.as_mut() {
        Some(task) => task.await,
        None => std::future::pending().await,
    }
}

/// Čeká, až má přihlášené spojení co dolévat; bez přihlášení nikdy.
async fn refill_due(device: &Option<Arc<crate::state::OnlineDevice>>) -> crate::state::QueueCursor {
    match device {
        Some(device) => device.refill_due().await,
        None => std::future::pending().await,
    }
}

/// Dolije spojení obálky, které se do jeho fronty nevešly.
async fn refill_work(
    state: Arc<AppState>,
    device: Arc<crate::state::OnlineDevice>,
    delivery_address: Vec<u8>,
    after: crate::state::QueueCursor,
) {
    if let Err(e) = state.refill_queue(&delivery_address, &device, after).await {
        tracing::warn!("dolití fronty selhalo: {e}");
    }
}

/// Kód odpojení z registru ověřených spojení. Bez registrace (před
/// AUTH_PROOF) nikdy nepřijde. Přijímač se po dokončení znovu pollovat
/// nesmí, proto se slot po zániku odesílatele vyprázdní.
async fn kicked(slot: &mut Option<oneshot::Receiver<u32>>) -> u32 {
    if let Some(receiver) = slot.as_mut() {
        match receiver.await {
            Ok(code) => return code,
            Err(_) => *slot = None,
        }
    }
    std::future::pending().await
}

async fn handle(state: Arc<AppState>, socket: WebSocket) {
    let (sink, stream) = socket.split();
    serve(state, sink, stream).await;
}

/// Jedno WS spojení nad libovolným sinkem a streamem zpráv (testy ho
/// pohánějí kanály bez sítě).
async fn serve<Si, St, E>(state: Arc<AppState>, sink: Si, mut stream: St)
where
    Si: Sink<WsMessage> + Send + Unpin + 'static,
    St: Stream<Item = Result<WsMessage, E>> + Unpin,
{
    let (outbox, queued) = outbox::channel();

    let mut writer = tokio::spawn(write_frames(sink, queued, WRITE_TIMEOUT));
    // Dokončený JoinHandle se nesmí pollovat znovu.
    let mut writer_done = false;

    let mut pending: Option<Pending> = None;
    let mut authed_address: Option<Vec<u8>> = None;
    // device_uuid ověřeného zařízení — klíč pro push registraci.
    let mut authed_device: Option<Vec<u8>> = None;
    let mut authed_account: Option<Account> = None;
    // Záznam v `online` mapě — značkuje se každým rámcem od klienta, aby
    // routing poznal živé spojení od zatuchlého.
    let mut online_device: Option<Arc<crate::state::OnlineDevice>> = None;
    // Záznam v registru ověřených spojení a kanál, kterým relay spojení
    // odpojí (blokace, smazání účtu, převzetí, úklid).
    let mut authed_conn: Option<crate::state::AuthedConnGuard> = None;
    let mut kick: Option<oneshot::Receiver<u32>> = None;
    let mut after_auth: Option<AfterAuth> = None;

    // Anti-abuse okno: počítá rámce, které něco stojí (viz FRAME_WINDOW_MAX)
    let mut window_start = Instant::now();
    let mut window_frames: u32 = 0;
    let auth_deadline = Instant::now() + AUTH_DEADLINE;
    let mut idle_deadline = Instant::now() + IDLE_TIMEOUT;
    let mut auth_attempts: u32 = 0;

    // Zařadí rámec z hlavní smyčky; odpojení a konec writeru smyčku ukončí.
    macro_rules! deliver {
        ($frame:expr) => {
            match push(&outbox, &mut kick, $frame).await {
                Pushed::Sent => {}
                Pushed::Kicked(code) => {
                    let _ = outbox.try_send(&error_frame(code, rejection_text(code)));
                    break;
                }
                Pushed::Closed => break,
            }
        };
    }
    // Poslední rámec před zavřením spojení. Bez čekání: komu se do fronty
    // nevejde, ten nečte a rámec by stejně nedostal.
    macro_rules! reject {
        ($frame:expr) => {{
            let _ = outbox.try_send(&$frame);
            break;
        }};
    }

    loop {
        // Před AUTH platí absolutní deadline — viset neautentizovaný nejde.
        // Po AUTH hlídá spojení idle timeout: klient, který dýchá, pošle
        // aspoň Pong na náš ping. Ticho = mrtvé spojení → zavřít, ať
        // záznam zmizí z `online` a další zpráva jde přes push budíček.
        // Bez tohohle tam zombie visel, dokud traefiku nedošel readTimeout
        // (30 min), a push se celou tu dobu vůbec nezkusil.
        let deadline = if authed_address.is_some() {
            idle_deadline
        } else {
            auth_deadline
        };
        // Odpojení z registru má přednost před dalším rámcem. Vylévání
        // fronty běží ve stejném selectu, ne uvnitř větve: nečtoucí klient
        // ho zastaví, ale smyčka dál vidí kick, ticho i konec writeru.
        let next = tokio::select! {
            biased;
            code = kicked(&mut kick) => {
                // Bez čekání: u klienta, který nečte, by plná fronta
                // zastavila smyčku a spojení by zůstalo v `online`.
                // Kdo rámec nedostane, uslyší kód při dalším AUTH.
                reject!(error_frame(code, rejection_text(code)))
            }
            _ = &mut writer => {
                writer_done = true;
                tracing::debug!("ws zavřeno: zápis klientovi selhal nebo vypršel");
                break;
            }
            () = finished(&mut after_auth) => {
                after_auth = None;
                continue;
            }
            // Obálky, které se do fronty spojení nevešly, čekají v DB.
            // Dolévá se až po práci po přihlášení (ta frontu vylévá celou)
            // a stejně jako ona vedle smyčky, ne v ní.
            after = refill_due(&online_device), if after_auth.is_none() => {
                if let (Some(device), Some(address)) = (&online_device, &authed_address) {
                    after_auth = Some(Box::pin(refill_work(
                        state.clone(),
                        device.clone(),
                        address.clone(),
                        after,
                    )));
                }
                continue;
            }
            next = tokio::time::timeout_at(deadline, stream.next()) => match next {
                Ok(next) => next,
                Err(_) if authed_address.is_none() => {
                    tracing::debug!("ws zavřeno: AUTH deadline");
                    break;
                }
                Err(_) => {
                    // info, ne debug: relay běží na RUST_LOG=info a kolik
                    // spojení umírá na ticho je provozní signál (kvalita sítě
                    // klientů), ne ladicí detail. Bez identifikátoru zařízení.
                    tracing::info!("ws zavřeno: klient neodpovídá na ping");
                    break;
                }
            },
        };
        let Some(Ok(msg)) = next else { break };

        // Cokoliv od klienta (i Pong na náš ping) = spojení dýchá.
        idle_deadline = Instant::now() + IDLE_TIMEOUT;
        if let Some(dev) = &online_device {
            dev.touch(state.now_ms());
        }

        let data = match msg {
            WsMessage::Binary(b) => b,
            WsMessage::Close(_) => break,
            _ => continue,
        };
        let Ok(frame) = v1::ClientFrame::decode(data.as_ref()) else {
            reject!(error_frame(400, "neplatný rámec"))
        };

        let cheap = matches!(
            frame.frame,
            Some(v1::client_frame::Frame::Ack(_)) | Some(v1::client_frame::Frame::Pong(_))
        );
        if !cheap {
            let now = Instant::now();
            if now.duration_since(window_start) > FRAME_WINDOW {
                window_start = now;
                window_frames = 0;
            }
            window_frames += 1;
            if window_frames > state.limits.ws_frames_per_window {
                reject!(error_frame(429, "příliš mnoho rámců"))
            }
        }

        match frame.frame {
            Some(v1::client_frame::Frame::Auth(auth)) if authed_address.is_none() => {
                auth_attempts += 1;
                if auth_attempts > MAX_AUTH_ATTEMPTS {
                    reject!(error_frame(429, "příliš mnoho AUTH pokusů"))
                }
                if auth.device_uuid.len() != 16 || auth.nonce_client.len() != 16 {
                    reject!(error_frame(400, "neplatný AUTH"))
                }
                let row = sqlx::query_as::<_, (Vec<u8>, Vec<u8>, Vec<u8>, DateTime<Utc>)>(
                    "SELECT d.delivery_address, i.identity_key, d.account_id, i.registered_at
                     FROM devices d JOIN identities i USING (account_id)
                     WHERE d.device_uuid = $1",
                )
                .bind(&auth.device_uuid)
                .fetch_optional(&state.pool)
                .await;
                // Výpadek DB není „neautorizováno": appka se má připojit znovu,
                // ne usoudit, že registrace skončila.
                let (delivery_address, identity_key, account_id, registered_at) = match row {
                    Ok(Some(row)) => row,
                    Ok(None) => {
                        reject!(missing_device_frame(&state, &auth.device_uuid).await)
                    }
                    Err(e) => {
                        tracing::warn!("AUTH: dotaz do DB selhal: {e}");
                        reject!(error_frame(503, TEXT_UNAVAILABLE))
                    }
                };
                let mut nonce_server = vec![0u8; 32];
                rand::rng().fill_bytes(&mut nonce_server);
                deliver!(server_frame(v1::server_frame::Frame::Challenge(
                    v1::Challenge {
                        nonce_server: nonce_server.clone(),
                    },
                )));
                pending = Some(Pending {
                    nonce_client: auth.nonce_client,
                    nonce_server,
                    delivery_address,
                    identity_key,
                    device_uuid: auth.device_uuid,
                    account_id,
                    registered_at,
                });
            }

            Some(v1::client_frame::Frame::AuthProof(proof)) if pending.is_some() => {
                let pd = pending.take().expect("pending ověřen výše");
                let mut message =
                    Vec::with_capacity(pd.nonce_client.len() + pd.nonce_server.len() + AUTH_CONTEXT.len());
                message.extend_from_slice(&pd.nonce_client);
                message.extend_from_slice(&pd.nonce_server);
                message.extend_from_slice(AUTH_CONTEXT);

                let verified = PublicKey::deserialize(&pd.identity_key)
                    .map(|pk| pk.verify_signature(&message, &proof.signature))
                    .unwrap_or(false);
                if !verified {
                    reject!(error_frame(401, "neplatný podpis"))
                }

                // Do registru dřív než zápis do DB: co se smaže před
                // zápisem, zachytí zápis (0 řádků), co se smaže po něm,
                // odpojí registr. Okno mezi tím nezůstane.
                let fingerprint = Fingerprint::of_identity_key(&pd.identity_key);
                let (guard, kicked_rx) = state.conns.add(pd.device_uuid.clone(), fingerprint.0);
                authed_conn = Some(guard);
                kick = Some(kicked_rx);

                // Podmíněný zápis zároveň ověří, že zařízení pořád existuje
                // (smazání mezi AUTH a důkazem = žádné AuthOk).
                // last_seen jen v hrubé granularitě (privacy, §1.2).
                let touched = sqlx::query(
                    "UPDATE devices SET last_seen_at = date_trunc('hour', now())
                     WHERE device_uuid = $1",
                )
                .bind(&pd.device_uuid)
                .execute(&state.pool)
                .await;
                match touched {
                    Ok(done) if done.rows_affected() > 0 => {}
                    Ok(_) => {
                        reject!(missing_device_frame(&state, &pd.device_uuid).await)
                    }
                    Err(e) => {
                        tracing::warn!("AUTH_PROOF: zápis do DB selhal: {e}");
                        reject!(error_frame(503, TEXT_UNAVAILABLE))
                    }
                }
                // Zařízení existuje, identita ale může být zablokovaná:
                // registrace vzniklá obejitím blokace čeká na hodinové
                // dorovnání a do té doby se nesmí přihlásit.
                match blocking::is_blocked(&state.pool, &fingerprint).await {
                    Ok(false) => {}
                    Ok(true) => {
                        reject!(error_frame(403, blocking::TEXT_BLOCKED))
                    }
                    Err(e) => {
                        tracing::warn!("AUTH_PROOF: kontrola blokace selhala: {e}");
                        reject!(error_frame(503, TEXT_UNAVAILABLE))
                    }
                }

                let device = Arc::new(crate::state::OnlineDevice::new(
                    outbox.clone(),
                    state.now_ms(),
                ));
                state
                    .online
                    .attach(pd.delivery_address.clone(), device.clone());
                online_device = Some(device.clone());
                authed_address = Some(pd.delivery_address.clone());
                // Člověk appku otevřel: další zprávy má zase slyšet.
                state.reset_alerts(&pd.delivery_address);

                // Potvrzení AUTH — klient až teď smí hlásit „připojeno"
                deliver!(server_frame(v1::server_frame::Frame::AuthOk(
                    v1::AuthOk {},
                )));

                after_auth = Some(Box::pin(after_auth_work(
                    state.clone(),
                    device,
                    pd.delivery_address,
                    pd.device_uuid.clone(),
                )));

                authed_device = Some(pd.device_uuid);
                authed_account = Some(Account {
                    id: pd.account_id,
                    registered_at: pd.registered_at,
                });
            }

            Some(v1::client_frame::Frame::RegisterPush(reg)) if authed_address.is_some() => {
                if let Some(device) = &authed_device {
                    let platform = i16::try_from(reg.platform).unwrap_or(-1);
                    if platform < 0 || platform > crate::push::PLATFORM_MAX {
                        deliver!(error_frame(400, "neznámá push platforma"));
                    } else if reg.endpoint.len() > MAX_PUSH_ENDPOINT_BYTES
                        || reg.voip_token.len() > MAX_VOIP_TOKEN_BYTES
                    {
                        deliver!(error_frame(400, "push endpoint je příliš dlouhý"));
                    } else if platform == crate::push::PLATFORM_APNS
                        && !apns_tokens_valid(&reg.endpoint, &reg.voip_token)
                    {
                        deliver!(error_frame(400, "neplatný APNs token"));
                    } else {
                        let endpoint =
                            (!reg.endpoint.is_empty()).then_some(reg.endpoint.as_slice());
                        // VoIP token dává smysl jen vedle APNs (PushKit je iOS).
                        let voip = (platform == crate::push::PLATFORM_APNS
                            && !reg.voip_token.is_empty())
                        .then_some(reg.voip_token.as_slice());
                        // Endpoint se ZÁMĚRNĚ neloguje (metadatový bod).
                        if let Err(e) =
                            state.register_push(device, platform, endpoint, voip).await
                        {
                            tracing::warn!("register_push selhal: {e}");
                        }
                    }
                }
            }

            Some(v1::client_frame::Frame::Envelope(envelope)) => {
                let (Some(address), Some(account)) = (&authed_address, &authed_account) else {
                    reject!(error_frame(400, "rámec mimo pořadí"))
                };
                let msg_uuid = envelope.msg_uuid.clone();
                let sender = crate::state::Sender {
                    account: &account.id,
                    address,
                    registered_at: account.registered_at,
                };
                match state.route_envelope(envelope, sender).await {
                    Ok(status) => {
                        deliver!(server_frame(v1::server_frame::Frame::Receipt(
                            v1::Receipt {
                                msg_uuid,
                                status: status as i32,
                            },
                        )));
                    }
                    // Plná fronta příjemce jde jako doručenka, ne jako Error:
                    // chybový rámec nenese msg_uuid a klienti do 1.2.7 ho
                    // nepárují, takže každé odeslání takovému příjemci
                    // čekalo deset sekund na timeout (rozesílka skupině je
                    // po jednom, zdržel ji celou). DROPPED říká pravdu —
                    // relay obálku neuložil — a u obálky, která není
                    // „píše…“, ho jinak neposílá, takže ho klient pozná.
                    Err(crate::state::RouteError::RecipientFull) => {
                        deliver!(server_frame(v1::server_frame::Frame::Receipt(
                            v1::Receipt {
                                msg_uuid,
                                status: v1::receipt::Status::Dropped as i32,
                            },
                        )));
                    }
                    Err(e) => {
                        if let crate::state::RouteError::Internal(err) = &e {
                            tracing::warn!("obálka neuložena: {err}");
                        }
                        let (code, message) = e.code_and_message();
                        deliver!(error_frame(code, message));
                    }
                }
            }

            Some(v1::client_frame::Frame::Ack(ack)) if authed_address.is_some() => {
                if let Some(addr) = &authed_address {
                    if let Err(e) = state.ack(addr, &ack.msg_uuid).await {
                        tracing::warn!("ack selhal: {e}");
                    }
                }
            }

            Some(v1::client_frame::Frame::TurnRequest(_)) if authed_address.is_some() => {
                let frame = match (&state.turn, &authed_account) {
                    (Some(turn), Some(account)) => {
                        let creds =
                            turn.credentials(&account.id, chrono::Utc::now().timestamp());
                        server_frame(v1::server_frame::Frame::TurnCredentials(creds))
                    }
                    _ => error_frame(503, "TURN není nakonfigurován"),
                };
                deliver!(frame);
            }

            Some(v1::client_frame::Frame::Pong(_)) => {}

            // 400, ne 403: kód 403 znamená jen zablokovanou identitu.
            _ => reject!(error_frame(400, "rámec mimo pořadí")),
        }
    }

    if let (Some(addr), Some(device)) = (&authed_address, &online_device) {
        state.online.detach(addr, device);
    }
    drop(authed_conn);
    // Writer dočerpá frontu a pošle Close, až zanikne poslední odesílač;
    // jeden drží `online_device`, další rozdělaná práce po přihlášení. Kdo
    // drží další klon (routing právě doručuje), na toho se čeká nejvýš
    // WRITER_DRAIN.
    drop(after_auth);
    drop(online_device);
    drop(outbox);
    if !writer_done
        && tokio::time::timeout(WRITER_DRAIN, &mut writer)
            .await
            .is_err()
    {
        writer.abort();
    }
    tracing::debug!("ws spojení uzavřeno");
}

/// Writer spojení: zapisuje rámce z fronty do sinku. Drží sink sám, takže
/// si i pinguje — jinak by control rámce musely téct přes frontu, která
/// nese jen aplikační ServerFrame. Skončí koncem fronty (pošle Close),
/// chybou zápisu, nebo když se rámec do `write_timeout` nezapíše.
async fn write_frames<Si>(mut sink: Si, mut queued: outbox::OutboxReceiver, write_timeout: Duration)
where
    Si: Sink<WsMessage> + Unpin,
{
    let mut ping = tokio::time::interval(PING_INTERVAL);
    // Zpožděné ticky se nedohánějí — po pauze chceme jeden ping, ne dávku.
    ping.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
    ping.tick().await; // první tick padne hned, ten nechceme

    loop {
        let (message, permit) = tokio::select! {
            frame = queued.recv() => match frame {
                Some(outbox::Queued { bytes, permit }) => (WsMessage::Binary(bytes), Some(permit)),
                // Konec fronty = konec spojení. Rámce před ním (i chybový
                // rámec odpojení) už jsou odeslané; Close dá klientovi
                // vědět hned, ne až po timeoutu.
                None => (WsMessage::Close(None), None),
            },
            _ = ping.tick() => (WsMessage::Ping(Bytes::new()), None),
        };
        let closing = matches!(message, WsMessage::Close(_));
        let written = tokio::time::timeout(write_timeout, sink.send(message)).await;
        // Rozpočet fronty se vrací až po zápisu do socketu: rámec rozepsaný
        // u nečtoucího klienta pořád drží paměť.
        drop(permit);
        if closing || !matches!(written, Ok(Ok(()))) {
            break;
        }
    }
}

/// Po AuthOk: vylije frontu a případně pošle hint na docházející prekeys.
async fn after_auth_work(
    state: Arc<AppState>,
    device: Arc<crate::state::OnlineDevice>,
    delivery_address: Vec<u8>,
    device_uuid: Vec<u8>,
) {
    match state.flush_queue(&delivery_address, &device).await {
        Ok(count) => tracing::info!(count, "klient autentizován, fronta vylita"),
        Err(e) => tracing::warn!("flush fronty selhal: {e}"),
    }

    // Docházející one-time prekeys: klient si je doplní přes
    // POST /v1/keys. Bez tohohle hintu zůstal účet po vyčerpání
    // natrvalo bez OTP.
    if let Ok(remaining) = state.one_time_prekey_count(&device_uuid).await {
        if remaining < PREKEYS_LOW_THRESHOLD {
            let hint = server_frame(v1::server_frame::Frame::PrekeysLow(v1::PrekeysLow {
                remaining: remaining.max(0) as u32,
            }));
            // Konec spojení během čekání na místo není chyba k hlášení.
            let _ = device.outbox.send(&hint).await;
        }
    }
}

#[cfg(test)]
mod tests {
    use tokio::sync::mpsc;

    use super::*;

    #[test]
    fn apns_registrace_bere_jen_hex_tokeny() {
        let token = "a1".repeat(32).into_bytes();
        assert!(apns_tokens_valid(&token, &token));
        assert!(apns_tokens_valid(&token, b""), "bez VoIP tokenu");
        assert!(apns_tokens_valid(b"", &token), "jen VoIP token");
        assert!(!apns_tokens_valid(b"../../3/device/x", &token));
        assert!(!apns_tokens_valid(&token, b"voip?x"));
        assert!(!apns_tokens_valid(&[0xff, 0xfe], b""), "není UTF-8");
    }

    fn deliver(payload_len: usize) -> v1::ServerFrame {
        server_frame(v1::server_frame::Frame::Deliver(v1::Envelope {
            payload: vec![0x5A; payload_len],
            ..Default::default()
        }))
    }

    /// Klient, který ze socketu nečte: zápis rámce nesmí viset bez konce.
    /// Writer po lhůtě skončí a tím zavře frontu, takže se probudí i ten,
    /// kdo čeká na místo v ní.
    #[tokio::test]
    async fn writer_neceka_na_nectouciho_klienta_bez_konce() {
        const SHORT_TIMEOUT: Duration = Duration::from_millis(50);
        // „Socket“ o jednom rámci, který nikdo nevybírá.
        let (socket, _never_read) = mpsc::channel::<WsMessage>(1);
        let sink = Box::pin(futures_util::sink::unfold(
            socket,
            |tx, message: WsMessage| async move {
                tx.send(message).await.map(|()| tx).map_err(|_| ())
            },
        ));
        let (outbox, queued) = outbox::channel();
        let writer = tokio::spawn(write_frames(sink, queued, SHORT_TIMEOUT));

        let frame = deliver(300 * 1024);
        while outbox.try_send(&frame) {}
        // Writer mezitím první rámec zapsal a o druhý stojí; doplnit místo,
        // které tím uvolnil, ať je fronta plná i teď.
        tokio::time::sleep(SHORT_TIMEOUT / 5).await;
        while outbox.try_send(&frame) {}
        let blocked = outbox.send(&frame);
        let waited = tokio::time::timeout(SHORT_TIMEOUT * 20, blocked)
            .await
            .expect("writer měl po lhůtě skončit a frontu zavřít");
        assert_eq!(waited, Err(outbox::Closed));
        writer.await.expect("writer");
    }

    /// Konec fronty: writer dopíše, co v ní je, a pošle Close.
    #[tokio::test]
    async fn writer_po_konci_fronty_posle_close() {
        let (socket, mut client) = mpsc::channel::<WsMessage>(8);
        let sink = Box::pin(futures_util::sink::unfold(
            socket,
            |tx, message: WsMessage| async move {
                tx.send(message).await.map(|()| tx).map_err(|_| ())
            },
        ));
        let (outbox, queued) = outbox::channel();
        let writer = tokio::spawn(write_frames(sink, queued, WRITE_TIMEOUT));
        assert!(outbox.try_send(&error_frame(410, rejection_text(410))));
        drop(outbox);
        assert!(matches!(client.recv().await, Some(WsMessage::Binary(_))));
        assert!(matches!(client.recv().await, Some(WsMessage::Close(_))));
        writer.await.expect("writer");
    }
}

#[cfg(test)]
mod db_tests {
    //! WS spojení nad reálným Postgresem: `serve` poháněný kanály bez sítě.
    //! #[ignore] — spouštět s DB: `cargo test -p sepot-relay -- --ignored`.
    use std::convert::Infallible;

    use base64::prelude::*;
    use tokio::sync::mpsc;

    use super::*;
    use crate::blocking::BlockOptions;
    use crate::testkit::{self, rand_bytes, TestIdentity};

    /// Jak dlouho test čeká na rámec. Kontrola živých spojení v testech
    /// neběží, odpojení musí přijít hned.
    const REPLY_TIMEOUT: Duration = Duration::from_secs(5);

    /// Klient na druhém konci `serve`.
    struct Client {
        to_relay: mpsc::Sender<WsMessage>,
        from_relay: mpsc::Receiver<WsMessage>,
    }

    fn connect(state: Arc<AppState>) -> Client {
        let (to_relay, relay_rx) = mpsc::channel::<WsMessage>(16);
        let (relay_tx, from_relay) = mpsc::channel::<WsMessage>(64);
        let stream = Box::pin(futures_util::stream::unfold(
            relay_rx,
            |mut rx| async move {
                rx.recv()
                    .await
                    .map(|message| (Ok::<_, Infallible>(message), rx))
            },
        ));
        let sink = Box::pin(futures_util::sink::unfold(
            relay_tx,
            |tx, message: WsMessage| async move { tx.send(message).await.map(|()| tx) },
        ));
        tokio::spawn(serve(state, sink, stream));
        Client {
            to_relay,
            from_relay,
        }
    }

    impl Client {
        async fn send(&self, frame: v1::client_frame::Frame) {
            let bytes = v1::ClientFrame { frame: Some(frame) }.encode_to_vec();
            self.to_relay
                .send(WsMessage::Binary(bytes.into()))
                .await
                .expect("relay čte");
        }

        /// Další aplikační rámec; None = relay spojení zavřel.
        async fn next(&mut self) -> Option<v1::server_frame::Frame> {
            loop {
                let message = tokio::time::timeout(REPLY_TIMEOUT, self.from_relay.recv())
                    .await
                    .expect("relay odpověděl včas");
                match message {
                    Some(WsMessage::Binary(bytes)) => {
                        return v1::ServerFrame::decode(bytes.as_ref())
                            .expect("rámec")
                            .frame
                    }
                    Some(WsMessage::Close(_)) | None => return None,
                    Some(_) => {}
                }
            }
        }

        /// Kód dalšího chybového rámce; ostatní rámce (PrekeysLow) přeskočí.
        async fn next_error(&mut self) -> u32 {
            loop {
                match self.next().await {
                    Some(v1::server_frame::Frame::Error(error)) => return error.code,
                    Some(_) => {}
                    None => panic!("spojení skončilo bez chybového rámce"),
                }
            }
        }

        async fn auth(&mut self, device_uuid: &[u8]) -> (Vec<u8>, Option<v1::server_frame::Frame>) {
            let nonce_client = rand_bytes(16);
            self.send(v1::client_frame::Frame::Auth(v1::Auth {
                device_uuid: device_uuid.to_vec(),
                nonce_client: nonce_client.clone(),
            }))
            .await;
            (nonce_client, self.next().await)
        }

        async fn prove(
            &mut self,
            identity: &TestIdentity,
            nonce_client: &[u8],
            nonce_server: &[u8],
        ) -> Option<v1::server_frame::Frame> {
            let mut message = nonce_client.to_vec();
            message.extend_from_slice(nonce_server);
            message.extend_from_slice(AUTH_CONTEXT);
            self.send(v1::client_frame::Frame::AuthProof(v1::AuthProof {
                signature: identity.sign(&message),
            }))
            .await;
            self.next().await
        }

        async fn log_in(&mut self, identity: &TestIdentity, device_uuid: &[u8]) {
            let (nonce_client, reply) = self.auth(device_uuid).await;
            let Some(v1::server_frame::Frame::Challenge(challenge)) = reply else {
                panic!("čekal jsem Challenge: {reply:?}");
            };
            let reply = self
                .prove(identity, &nonce_client, &challenge.nonce_server)
                .await;
            assert!(
                matches!(reply, Some(v1::server_frame::Frame::AuthOk(_))),
                "{reply:?}"
            );
        }
    }

    fn error_code(frame: Option<v1::server_frame::Frame>) -> u32 {
        match frame {
            Some(v1::server_frame::Frame::Error(error)) => error.code,
            other => panic!("čekal jsem chybový rámec: {other:?}"),
        }
    }

    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn auth_ws_vraci_403_410_503() {
        let state = Arc::new(testkit::state().await);
        let identity = TestIdentity::new();
        let address = rand_bytes(32);
        let registered = testkit::register(&state, &identity, &address)
            .await
            .expect("registrace");
        blocking::block(&state.pool, &identity.fingerprint, BlockOptions::default())
            .await
            .expect("blokace");

        let mut client = connect(state.clone());
        let (_, reply) = client.auth(&registered.device_uuid).await;
        assert_eq!(error_code(reply), 403, "zařízení smazala blokace");
        assert!(client.next().await.is_none(), "spojení zavřené");

        let mut client = connect(state.clone());
        let (_, reply) = client.auth(&rand_bytes(16)).await;
        assert_eq!(error_code(reply), 410, "neznámé zařízení");
        assert!(client.next().await.is_none(), "spojení zavřené");

        let unavailable = Arc::new(testkit::state().await);
        unavailable.pool.close().await;
        let mut client = connect(unavailable);
        let (_, reply) = client.auth(&rand_bytes(16)).await;
        assert_eq!(error_code(reply), 503, "výpadek DB");
        assert!(client.next().await.is_none(), "spojení zavřené");

        testkit::forget(&state.pool, &identity, &[&address]).await;
    }

    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn auth_proof_po_smazani_zarizeni_vrati_410() {
        let state = Arc::new(testkit::state().await);
        let identity = TestIdentity::new();
        let address = rand_bytes(32);
        let registered = testkit::register(&state, &identity, &address)
            .await
            .expect("registrace");

        let mut client = connect(state.clone());
        let (nonce_client, reply) = client.auth(&registered.device_uuid).await;
        let Some(v1::server_frame::Frame::Challenge(challenge)) = reply else {
            panic!("čekal jsem Challenge: {reply:?}");
        };
        state
            .delete_identity(&registered.account_id)
            .await
            .expect("smazání účtu");
        let reply = client
            .prove(&identity, &nonce_client, &challenge.nonce_server)
            .await;
        assert_eq!(error_code(reply), 410);
        assert!(
            client.next().await.is_none(),
            "žádné AuthOk, spojení zavřené"
        );
        assert!(state.conns.snapshot().is_empty(), "registr bez spojení");

        testkit::forget(&state.pool, &identity, &[&address]).await;
    }

    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn smazani_a_prevzeti_odpoji_hned() {
        let state = Arc::new(testkit::state().await);

        let deleted = TestIdentity::new();
        let deleted_address = rand_bytes(32);
        let registered = testkit::register(&state, &deleted, &deleted_address)
            .await
            .expect("registrace");
        let mut client = connect(state.clone());
        client.log_in(&deleted, &registered.device_uuid).await;
        let headers = deleted.auth_headers(&registered.device_uuid, "DELETE /v1/identity");
        crate::rest::delete_identity(State(state.clone()), headers)
            .await
            .expect("smazání účtu");
        assert_eq!(client.next_error().await, 410);
        assert!(client.next().await.is_none(), "spojení zavřené");

        let restored = TestIdentity::new();
        let address = rand_bytes(32);
        let old = testkit::register(&state, &restored, &address)
            .await
            .expect("registrace");
        let mut client = connect(state.clone());
        client.log_in(&restored, &old.device_uuid).await;
        let new = testkit::register(&state, &restored, &address)
            .await
            .expect("převzetí");
        assert_ne!(new.device_uuid, old.device_uuid);
        assert_eq!(client.next_error().await, 410, "staré zařízení odpojeno");
        assert!(client.next().await.is_none(), "spojení zavřené");

        testkit::forget(&state.pool, &deleted, &[&deleted_address]).await;
        testkit::forget(&state.pool, &restored, &[&address]).await;
    }

    /// Registrace zablokované identity (vzniklá obejitím blokace) se do
    /// dorovnání nesmí přihlásit: zařízení v DB je, rozhoduje otisk.
    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn auth_proof_zablokovane_registrace_vrati_403() {
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

        let mut client = connect(state.clone());
        let (nonce_client, reply) = client.auth(&registered.device_uuid).await;
        let Some(v1::server_frame::Frame::Challenge(challenge)) = reply else {
            panic!("čekal jsem Challenge: {reply:?}");
        };
        let reply = client
            .prove(&identity, &nonce_client, &challenge.nonce_server)
            .await;
        assert_eq!(error_code(reply), 403);
        assert!(
            client.next().await.is_none(),
            "žádné AuthOk, spojení zavřené"
        );
        assert!(state.online.get(&address).is_none(), "adresa není online");

        testkit::forget(&state.pool, &identity, &[&address]).await;
    }

    /// Klient přestal číst a kanál k writeru je plný: odpojení nesmí čekat
    /// na místo v kanálu, jinak spojení zůstane v `online` a obálky pro
    /// smazanou adresu se dál přijímají do fronty.
    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn kick_odpoji_i_klienta_ktery_necte() {
        /// Víc obálek, než pojme kanál k writeru i „socket“ testovacího klienta.
        const ENVELOPES: usize = 200;
        let state = Arc::new(testkit::state().await);
        let identity = TestIdentity::new();
        let address = rand_bytes(32);
        let registered = testkit::register(&state, &identity, &address)
            .await
            .expect("registrace");
        let mut client = connect(state.clone());
        client.log_in(&identity, &registered.device_uuid).await;

        let account = rand_bytes(16);
        let sender = crate::state::Sender {
            account: &account,
            address: &[],
            registered_at: DateTime::UNIX_EPOCH,
        };
        let envelope = |address: &[u8]| v1::Envelope {
            dst_address: address.to_vec(),
            msg_uuid: rand_bytes(16),
            payload: rand_bytes(64),
            ..Default::default()
        };
        for _ in 0..ENVELOPES {
            // Plný kanál obálku odmítne nebo uloží do fronty; obojí je tu v pořádku.
            let _ = state.route_envelope(envelope(&address), sender).await;
        }
        blocking::block(&state.pool, &identity.fingerprint, BlockOptions::default())
            .await
            .expect("blokace");
        state.check_live_connections().await.expect("kontrola");

        let deadline = Instant::now() + WRITER_DRAIN + Duration::from_secs(1);
        while state.online.get(&address).is_some() && Instant::now() < deadline {
            tokio::time::sleep(Duration::from_millis(50)).await;
        }
        assert!(
            state.online.get(&address).is_none(),
            "spojení zůstalo v online"
        );
        assert!(state.conns.snapshot().is_empty(), "registr bez spojení");

        let routed = state.route_envelope(envelope(&address), sender).await;
        assert!(routed.is_err(), "smazaná adresa nepřijímá obálky");
        let queued = testkit::count(
            &state.pool,
            "SELECT count(*) FROM message_queue WHERE dst_address = $1",
            &address,
        )
        .await;
        assert_eq!(queued, 0, "fronta smazané adresy");

        drop(client);
        testkit::forget(&state.pool, &identity, &[&address]).await;
    }

    /// Zablokovaný klient s plnou frontou zpráv, který po přihlášení
    /// nečte: vylévání fronty se o něj zastaví, ale odpojení musí projít.
    /// Dřív smyčka spojení stála uvnitř vylévání, kick neviděla a adresa
    /// zůstala v `online`.
    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn kick_odpoji_klienta_ktery_necte_a_ma_plnou_frontu() {
        /// Víc, než pojme fronta spojení i „socket“ testovacího klienta
        /// dohromady: vylévání musí zůstat stát uprostřed.
        const QUEUED: usize = 200;
        const PAYLOAD_BYTES: usize = 16 * 1024;
        let state = Arc::new(testkit::state().await);
        let identity = TestIdentity::new();
        let address = rand_bytes(32);
        let registered = testkit::register(&state, &identity, &address)
            .await
            .expect("registrace");
        for _ in 0..QUEUED {
            let envelope = v1::Envelope {
                dst_address: address.clone(),
                msg_uuid: rand_bytes(16),
                payload: rand_bytes(PAYLOAD_BYTES),
                ..Default::default()
            };
            sqlx::query(
                "INSERT INTO message_queue (msg_uuid, dst_address, envelope, expires_at)
                 VALUES ($1, $2, $3, now() + interval '1 day')",
            )
            .bind(&envelope.msg_uuid)
            .bind(&address)
            .bind(envelope.encode_to_vec())
            .execute(&state.pool)
            .await
            .expect("obálka");
        }

        let mut client = connect(state.clone());
        client.log_in(&identity, &registered.device_uuid).await;
        // Nechat vylévání doběhnout až k plné frontě spojení.
        tokio::time::sleep(Duration::from_millis(300)).await;
        assert!(state.online.get(&address).is_some(), "spojení je online");

        blocking::block(&state.pool, &identity.fingerprint, BlockOptions::default())
            .await
            .expect("blokace");
        state.check_live_connections().await.expect("kontrola");

        let deadline = Instant::now() + WRITER_DRAIN + Duration::from_secs(1);
        while state.online.get(&address).is_some() && Instant::now() < deadline {
            tokio::time::sleep(Duration::from_millis(50)).await;
        }
        assert!(
            state.online.get(&address).is_none(),
            "spojení zůstalo v online"
        );
        assert!(state.conns.snapshot().is_empty(), "registr bez spojení");

        drop(client);
        testkit::forget(&state.pool, &identity, &[&address]).await;
    }

    fn envelope(dst: &[u8], payload_bytes: usize) -> v1::Envelope {
        v1::Envelope {
            dst_address: dst.to_vec(),
            msg_uuid: rand_bytes(16),
            payload: rand_bytes(payload_bytes),
            ..Default::default()
        }
    }

    /// Plná fronta příjemce: odesílatel dostane hned doručenku se svým
    /// msg_uuid (DROPPED), ne chybový rámec, na který klienti do 1.2.7
    /// čekali deset sekund. Opakovaná, už uložená obálka dostane běžnou.
    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn plna_fronta_prijemce_vraci_dorucenku_s_msg_uuid() {
        let mut state = testkit::state().await;
        state.limits.queue_max_per_recipient = 1;
        let state = Arc::new(state);
        let (sender, recipient) = (TestIdentity::new(), TestIdentity::new());
        let (sender_address, recipient_address) = (rand_bytes(32), rand_bytes(32));
        let registered = testkit::register(&state, &sender, &sender_address)
            .await
            .expect("registrace");
        testkit::register(&state, &recipient, &recipient_address)
            .await
            .expect("registrace");
        let mut client = connect(state.clone());
        client.log_in(&sender, &registered.device_uuid).await;

        let stored = envelope(&recipient_address, 64);
        let refused = envelope(&recipient_address, 64);
        let mut receipt_for = async |sent: &v1::Envelope| {
            client
                .send(v1::client_frame::Frame::Envelope(sent.clone()))
                .await;
            loop {
                match client.next().await {
                    Some(v1::server_frame::Frame::Receipt(receipt)) => {
                        assert_eq!(receipt.msg_uuid, sent.msg_uuid);
                        return receipt.status;
                    }
                    Some(v1::server_frame::Frame::Error(error)) => {
                        panic!("chybový rámec místo doručenky: {}", error.code)
                    }
                    Some(_) => {}
                    None => panic!("spojení skončilo bez doručenky"),
                }
            }
        };
        let stored_offline = v1::receipt::Status::StoredOffline as i32;
        assert_eq!(receipt_for(&stored).await, stored_offline);
        assert_eq!(
            receipt_for(&refused).await,
            v1::receipt::Status::Dropped as i32,
            "plná fronta"
        );
        assert_eq!(receipt_for(&stored).await, stored_offline, "opakovaná obálka");

        let queued: Vec<Vec<u8>> =
            sqlx::query_scalar("SELECT msg_uuid FROM message_queue WHERE dst_address = $1")
                .bind(&recipient_address)
                .fetch_all(&state.pool)
                .await
                .unwrap();
        assert_eq!(queued, vec![stored.msg_uuid], "odmítnutá obálka se neuložila");

        drop(client);
        testkit::forget(&state.pool, &sender, &[&sender_address]).await;
        testkit::forget(&state.pool, &recipient, &[&recipient_address]).await;
    }

    /// Obálky, které se připojenému příjemci nevešly do fronty spojení,
    /// mu relay dolije, jakmile začne číst — ne až po dalším připojení.
    /// Každá přijde právě jednou.
    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn pripojenemu_prijemci_se_zmeskane_obalky_doliji() {
        /// Víc, než pojme fronta spojení i „socket“ testovacího klienta.
        const SENT: usize = 300;
        const PAYLOAD_BYTES: usize = 16 * 1024;
        let state = Arc::new(testkit::state().await);
        let recipient = TestIdentity::new();
        let address = rand_bytes(32);
        let registered = testkit::register(&state, &recipient, &address)
            .await
            .expect("registrace");
        let mut client = connect(state.clone());
        client.log_in(&recipient, &registered.device_uuid).await;
        // Vylití prázdné fronty po přihlášení nechat doběhnout.
        tokio::time::sleep(Duration::from_millis(200)).await;

        let sender_account = rand_bytes(16);
        let sender = || crate::state::Sender {
            account: &sender_account,
            address: &[],
            registered_at: chrono::Utc::now() - chrono::Duration::days(30),
        };
        let mut expected = std::collections::HashSet::new();
        let mut stored_only = 0;
        for _ in 0..SENT {
            let sent = envelope(&address, PAYLOAD_BYTES);
            expected.insert(sent.msg_uuid.clone());
            let status = state.route_envelope(sent, sender()).await.expect("obálka");
            if status == v1::receipt::Status::StoredOffline {
                stored_only += 1;
            }
        }
        assert!(stored_only > 0, "test má frontu spojení přeplnit");

        let mut delivered = Vec::new();
        while delivered.len() < SENT {
            match client.next().await {
                Some(v1::server_frame::Frame::Deliver(got)) => delivered.push(got.msg_uuid),
                Some(_) => {}
                None => panic!("spojení skončilo po {} obálkách", delivered.len()),
            }
        }
        let distinct: std::collections::HashSet<_> = delivered.iter().cloned().collect();
        assert_eq!(distinct, expected, "každá obálka došla");
        assert_eq!(delivered.len(), distinct.len(), "žádná dvakrát");

        drop(client);
        testkit::forget(&state.pool, &recipient, &[&address]).await;
    }

    /// Všechny podoby identifikátoru, jak by se mohl dostat do logu.
    fn log_forms(value: &[u8]) -> Vec<String> {
        /// Prefix, podle kterého se pozná i zkrácený výpis.
        const PREFIX_BYTES: usize = 8;
        let mut forms = vec![
            hex::encode(value),
            hex::encode_upper(value),
            BASE64_STANDARD.encode(value),
            BASE64_URL_SAFE_NO_PAD.encode(value),
        ];
        if value.len() >= PREFIX_BYTES {
            forms.push(hex::encode(&value[..PREFIX_BYTES]));
        }
        forms
    }

    /// Relay nesmí logovat identifikátory: klíče, otisky, účty, zařízení ani
    /// adresy. Projde blokaci, převzetí, odpojení, smazání účtu, údržbu
    /// a výpadek DB a v zachyceném logu je hledá ve všech podobách.
    #[tokio::test]
    #[ignore = "vyžaduje běžící Postgres (dev DB)"]
    async fn logy_bez_identifikatoru() {
        let log = testkit::LogCapture::default();
        let _guard = log.start();
        let isolated = testkit::Isolated::new().await;
        let mut state = isolated.state().await;
        state.limits.inactive_cleanup = true;
        let state = Arc::new(state);
        let pool = &isolated.pool;
        let mut secrets: Vec<Vec<u8>> = Vec::new();
        let mut fingerprints = Vec::new();

        // Registrace, převzetí, push, blokace se zajištěním, odmítnutá registrace.
        let taken_over = TestIdentity::new();
        let (first_address, second_address) = (rand_bytes(32), rand_bytes(32));
        let first = testkit::register(&state, &taken_over, &first_address)
            .await
            .expect("registrace");
        let second = testkit::register(&state, &taken_over, &second_address)
            .await
            .expect("převzetí");
        state
            .register_push(
                &second.device_uuid,
                crate::push::PLATFORM_FCM,
                Some(b"fcm"),
                None,
            )
            .await
            .expect("push");
        let hold = BlockOptions {
            hold: true,
            ..BlockOptions::default()
        };
        blocking::block(pool, &taken_over.fingerprint, hold)
            .await
            .expect("blokace");
        let Err(error) = testkit::register(&state, &taken_over, &rand_bytes(32)).await else {
            panic!("zablokovaná identita se zaregistrovala");
        };
        assert_eq!(error.status, StatusCode::FORBIDDEN);
        secrets.extend([
            taken_over.key.clone(),
            first.account_id,
            first.device_uuid,
            second.device_uuid,
            first_address,
            second_address,
        ]);
        fingerprints.push(taken_over.fingerprint);

        // Přihlášené spojení, blokace jiným procesem, kontrola spojení,
        // pak AUTH zablokovaného a neznámého zařízení.
        let kicked = TestIdentity::new();
        let kicked_address = rand_bytes(32);
        let registered = testkit::register(&state, &kicked, &kicked_address)
            .await
            .expect("registrace");
        let mut client = connect(state.clone());
        client.log_in(&kicked, &registered.device_uuid).await;
        blocking::block(pool, &kicked.fingerprint, BlockOptions::default())
            .await
            .expect("blokace");
        state.check_live_connections().await.expect("kontrola");
        assert_eq!(client.next_error().await, 403);
        let (_, reply) = connect(state.clone()).auth(&registered.device_uuid).await;
        assert_eq!(error_code(reply), 403);
        let unknown_device = rand_bytes(16);
        let (_, reply) = connect(state.clone()).auth(&unknown_device).await;
        assert_eq!(error_code(reply), 410);
        secrets.extend([
            kicked.key.clone(),
            registered.account_id,
            registered.device_uuid,
            kicked_address,
            unknown_device,
        ]);
        fingerprints.push(kicked.fingerprint);

        // Smazání účtu přes handler, odpojení 410.
        let deleted = TestIdentity::new();
        let deleted_address = rand_bytes(32);
        let registered = testkit::register(&state, &deleted, &deleted_address)
            .await
            .expect("registrace");
        let mut client = connect(state.clone());
        client.log_in(&deleted, &registered.device_uuid).await;
        let headers = deleted.auth_headers(&registered.device_uuid, "DELETE /v1/identity");
        crate::rest::delete_identity(State(state.clone()), headers)
            .await
            .expect("smazání účtu");
        assert_eq!(client.next_error().await, 410);
        secrets.extend([
            deleted.key.clone(),
            registered.account_id,
            registered.device_uuid,
            deleted_address,
        ]);

        // Údržba: dorovnání registrace zablokované identity a úklid
        // neaktivní registrace.
        let reconciled = TestIdentity::new();
        blocking::block(pool, &reconciled.fingerprint, BlockOptions::default())
            .await
            .expect("blokace");
        let (account_id, device_uuid, address) = (rand_bytes(16), rand_bytes(16), rand_bytes(32));
        sqlx::query("INSERT INTO identities (account_id, identity_key) VALUES ($1, $2)")
            .bind(&account_id)
            .bind(&reconciled.key)
            .execute(pool)
            .await
            .unwrap();
        sqlx::query(
            "INSERT INTO devices (device_uuid, account_id, device_id, registration_id, delivery_address)
             VALUES ($1, $2, 1, 1, $3)",
        )
        .bind(&device_uuid)
        .bind(&account_id)
        .bind(&address)
        .execute(pool)
        .await
        .unwrap();
        secrets.extend([reconciled.key.clone(), account_id, device_uuid, address]);
        fingerprints.push(reconciled.fingerprint);
        let inactive = TestIdentity::new();
        let (account_id, device_uuid, address) = (rand_bytes(16), rand_bytes(16), rand_bytes(32));
        sqlx::query(
            "INSERT INTO identities (account_id, identity_key, registered_at)
             VALUES ($1, $2, now() - interval '400 days')",
        )
        .bind(&account_id)
        .bind(&inactive.key)
        .execute(pool)
        .await
        .unwrap();
        sqlx::query(
            "INSERT INTO devices (device_uuid, account_id, device_id, registration_id,
                                  delivery_address, created_at, last_seen_at)
             VALUES ($1, $2, 1, 1, $3, now() - interval '400 days', now() - interval '390 days')",
        )
        .bind(&device_uuid)
        .bind(&account_id)
        .bind(&address)
        .execute(pool)
        .await
        .unwrap();
        secrets.extend([inactive.key.clone(), account_id, device_uuid, address]);
        state.maintain_blocks().await;
        state.clean_inactive().await;

        // Výpadek DB: AUTH 503, kontrola spojení a údržba jen s chybou.
        let unavailable = Arc::new(isolated.state().await);
        let live_device = rand_bytes(16);
        let (_live, _kick) = unavailable
            .conns
            .add(live_device.clone(), kicked.fingerprint.0);
        unavailable.pool.close().await;
        let (_, reply) = connect(unavailable.clone()).auth(&live_device).await;
        assert_eq!(error_code(reply), 503);
        assert!(unavailable.check_live_connections().await.is_err());
        unavailable.maintain_blocks().await;
        secrets.push(live_device);

        let text = log.text();
        assert!(
            text.contains("registrace zablokované identity odmítnuta"),
            "{text}"
        );
        assert!(text.contains("odpojeno_403=1"), "{text}");
        assert!(text.contains("dorovnano=1"), "{text}");
        assert!(text.contains("uklid=1"), "{text}");
        let mut leaked: Vec<String> = secrets
            .iter()
            .flat_map(|secret| log_forms(secret))
            .filter(|form| text.contains(form.as_str()))
            .collect();
        for fingerprint in &fingerprints {
            leaked.extend(
                log_forms(&fingerprint.0)
                    .into_iter()
                    .chain([fingerprint.to_crockford(), fingerprint.short()])
                    .filter(|form| text.contains(form.as_str())),
            );
        }
        assert!(leaked.is_empty(), "identifikátory v logu: {leaked:?}");
        isolated.remove().await;
    }
}
