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
use futures_util::{SinkExt, StreamExt};
use libsignal_protocol::PublicKey;
use prost::Message;
use rand::RngCore;
use sepot_proto::{v1, AUTH_CONTEXT, MAX_ENVELOPE_PAYLOAD};
use tokio::sync::mpsc;
use tokio::time::Instant;

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
/// TURN údaje platí hodiny — nové vydat nejdřív po tomhle čase, jinak se
/// na jednom spojení dají farmit stovky přihlášení (kvóta coturnu je na jméno).
const TURN_REISSUE_AFTER: Duration = Duration::from_secs(600);
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
    let ip = state.trusted_proxies.client_ip(peer.ip(), &headers);
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

async fn handle(state: Arc<AppState>, socket: WebSocket) {
    let (mut sink, mut stream) = socket.split();
    let (tx, mut rx) = mpsc::channel::<v1::ServerFrame>(64);

    // Writer drží sink sám, takže si i pinguje — jinak by control rámce
    // musely téct přes `tx`, který nese jen aplikační ServerFrame.
    let writer = tokio::spawn(async move {
        let mut ping = tokio::time::interval(PING_INTERVAL);
        // Zpožděné ticky se nedohánějí — po pauze chceme jeden ping, ne dávku.
        ping.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
        ping.tick().await; // první tick padne hned, ten nechceme

        loop {
            tokio::select! {
                frame = rx.recv() => {
                    let Some(frame) = frame else { break };
                    let bytes = frame.encode_to_vec();
                    if sink.send(WsMessage::Binary(bytes.into())).await.is_err() {
                        break;
                    }
                }
                _ = ping.tick() => {
                    if sink.send(WsMessage::Ping(Bytes::new())).await.is_err() {
                        break;
                    }
                }
            }
        }
    });

    let mut pending: Option<Pending> = None;
    let mut authed_address: Option<Vec<u8>> = None;
    // device_uuid ověřeného zařízení — klíč pro push registraci.
    let mut authed_device: Option<Vec<u8>> = None;
    // Účet ověřeného zařízení — klíč kvóty odesílatele (jen v paměti).
    let mut authed_account: Option<Vec<u8>> = None;
    // Záznam v `online` mapě — značkuje se každým rámcem od klienta, aby
    // routing poznal živé spojení od zatuchlého.
    let mut online_device: Option<Arc<crate::state::OnlineDevice>> = None;

    // Anti-abuse okno: počítá rámce, které něco stojí (viz FRAME_WINDOW_MAX)
    let mut window_start = Instant::now();
    let mut window_frames: u32 = 0;
    let auth_deadline = Instant::now() + AUTH_DEADLINE;
    let mut auth_attempts: u32 = 0;
    // Naposledy vydané TURN údaje — do TURN_REISSUE_AFTER se vrací tytéž.
    let mut turn_issued: Option<(Instant, v1::TurnCredentials)> = None;

    loop {
        // Před AUTH platí absolutní deadline — viset neautentizovaný nejde
        let next = if authed_address.is_none() {
            match tokio::time::timeout_at(auth_deadline, stream.next()).await {
                Ok(next) => next,
                Err(_) => {
                    tracing::debug!("ws zavřeno: AUTH deadline");
                    break;
                }
            }
        } else {
            // Po AUTH hlídá spojení idle timeout: klient, který dýchá, pošle
            // aspoň Pong na náš ping. Ticho = mrtvé spojení → zavřít, ať
            // záznam zmizí z `online` a další zpráva jde přes push budíček.
            // Bez tohohle tam zombie visel, dokud traefiku nedošel readTimeout
            // (30 min), a push se celou tu dobu vůbec nezkusil.
            match tokio::time::timeout(IDLE_TIMEOUT, stream.next()).await {
                Ok(next) => next,
                Err(_) => {
                    // info, ne debug: relay běží na RUST_LOG=info a kolik
                    // spojení umírá na ticho je provozní signál (kvalita sítě
                    // klientů), ne ladicí detail. Bez identifikátoru zařízení.
                    tracing::info!("ws zavřeno: klient neodpovídá na ping");
                    break;
                }
            }
        };
        let Some(Ok(msg)) = next else { break };

        // Cokoliv od klienta (i Pong na náš ping) = spojení dýchá.
        if let Some(dev) = &online_device {
            dev.touch(state.now_ms());
        }

        let data = match msg {
            WsMessage::Binary(b) => b,
            WsMessage::Close(_) => break,
            _ => continue,
        };
        let Ok(frame) = v1::ClientFrame::decode(data.as_ref()) else {
            let _ = tx.send(error_frame(400, "neplatný rámec")).await;
            break;
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
                let _ = tx.send(error_frame(429, "příliš mnoho rámců")).await;
                break;
            }
        }

        match frame.frame {
            Some(v1::client_frame::Frame::Auth(auth)) if authed_address.is_none() => {
                auth_attempts += 1;
                if auth_attempts > MAX_AUTH_ATTEMPTS {
                    let _ = tx.send(error_frame(429, "příliš mnoho AUTH pokusů")).await;
                    break;
                }
                if auth.device_uuid.len() != 16 || auth.nonce_client.len() != 16 {
                    let _ = tx.send(error_frame(400, "neplatný AUTH")).await;
                    break;
                }
                let row: Option<(Vec<u8>, Vec<u8>, Vec<u8>)> = sqlx::query_as(
                    "SELECT d.delivery_address, i.identity_key, d.account_id
                     FROM devices d JOIN identities i USING (account_id)
                     WHERE d.device_uuid = $1",
                )
                .bind(&auth.device_uuid)
                .fetch_optional(&state.pool)
                .await
                .ok()
                .flatten();
                let Some((delivery_address, identity_key, account_id)) = row else {
                    let _ = tx.send(error_frame(401, "neautorizováno")).await;
                    break;
                };
                let mut nonce_server = vec![0u8; 32];
                rand::rng().fill_bytes(&mut nonce_server);
                let _ = tx
                    .send(server_frame(v1::server_frame::Frame::Challenge(
                        v1::Challenge {
                            nonce_server: nonce_server.clone(),
                        },
                    )))
                    .await;
                pending = Some(Pending {
                    nonce_client: auth.nonce_client,
                    nonce_server,
                    delivery_address,
                    identity_key,
                    device_uuid: auth.device_uuid,
                    account_id,
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
                    let _ = tx.send(error_frame(401, "neplatný podpis")).await;
                    break;
                }

                let device = Arc::new(crate::state::OnlineDevice::new(
                    tx.clone(),
                    state.now_ms(),
                ));
                state
                    .online
                    .attach(pd.delivery_address.clone(), device.clone());
                online_device = Some(device);
                authed_address = Some(pd.delivery_address.clone());

                // Potvrzení AUTH — klient až teď smí hlásit „připojeno"
                let _ = tx
                    .send(server_frame(v1::server_frame::Frame::AuthOk(
                        v1::AuthOk {},
                    )))
                    .await;

                // last_seen jen v hrubé granularitě (privacy, §1.2).
                let _ = sqlx::query(
                    "UPDATE devices SET last_seen_at = date_trunc('hour', now())
                     WHERE device_uuid = $1",
                )
                .bind(&pd.device_uuid)
                .execute(&state.pool)
                .await;

                match state.flush_queue(&pd.delivery_address, &tx).await {
                    Ok(count) => {
                        tracing::info!(count, "klient autentizován, fronta vylita")
                    }
                    Err(e) => tracing::warn!("flush fronty selhal: {e}"),
                }

                // Docházející one-time prekeys: klient si je doplní přes
                // POST /v1/keys. Bez tohohle hintu zůstal účet po vyčerpání
                // natrvalo bez OTP.
                if let Ok(remaining) = state.one_time_prekey_count(&pd.device_uuid).await {
                    if remaining < PREKEYS_LOW_THRESHOLD {
                        let _ = tx
                            .send(server_frame(v1::server_frame::Frame::PrekeysLow(
                                v1::PrekeysLow {
                                    remaining: remaining.max(0) as u32,
                                },
                            )))
                            .await;
                    }
                }

                authed_device = Some(pd.device_uuid);
                authed_account = Some(pd.account_id);
            }

            Some(v1::client_frame::Frame::RegisterPush(reg)) if authed_address.is_some() => {
                if let Some(device) = &authed_device {
                    let platform = i16::try_from(reg.platform).unwrap_or(-1);
                    if platform < 0 || platform > crate::push::PLATFORM_MAX {
                        let _ = tx.send(error_frame(400, "neznámá push platforma")).await;
                    } else if reg.endpoint.len() > MAX_PUSH_ENDPOINT_BYTES
                        || reg.voip_token.len() > MAX_VOIP_TOKEN_BYTES
                    {
                        let _ = tx.send(error_frame(400, "push endpoint je příliš dlouhý")).await;
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

            Some(v1::client_frame::Frame::Envelope(envelope)) if authed_address.is_some() => {
                let msg_uuid = envelope.msg_uuid.clone();
                let sender = authed_account.as_deref().unwrap_or_default();
                match state.route_envelope(envelope, sender).await {
                    Ok(status) => {
                        let _ = tx
                            .send(server_frame(v1::server_frame::Frame::Receipt(
                                v1::Receipt {
                                    msg_uuid,
                                    status: status as i32,
                                },
                            )))
                            .await;
                    }
                    Err(e) => {
                        if let crate::state::RouteError::Internal(err) = &e {
                            tracing::warn!("obálka neuložena: {err}");
                        }
                        let (code, message) = e.code_and_message();
                        let _ = tx.send(error_frame(code, message)).await;
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
                let frame = match &state.turn {
                    Some(turn) => {
                        let fresh = turn_issued
                            .as_ref()
                            .filter(|(at, _)| at.elapsed() < TURN_REISSUE_AFTER)
                            .map(|(_, c)| c.clone());
                        let creds = match fresh {
                            Some(c) => c,
                            None => {
                                let c = turn.credentials(chrono::Utc::now().timestamp());
                                turn_issued = Some((Instant::now(), c.clone()));
                                c
                            }
                        };
                        server_frame(v1::server_frame::Frame::TurnCredentials(creds))
                    }
                    None => error_frame(503, "TURN není nakonfigurován"),
                };
                let _ = tx.send(frame).await;
            }

            Some(v1::client_frame::Frame::Pong(_)) => {}

            _ => {
                let _ = tx.send(error_frame(403, "rámec mimo pořadí")).await;
                break;
            }
        }
    }

    if let (Some(addr), Some(device)) = (&authed_address, &online_device) {
        state.online.detach(addr, device);
    }
    writer.abort();
    tracing::debug!("ws spojení uzavřeno");
}
