//! Šepot relay — hloupý store-and-forward server.
//!
//! Nevidí obsah (E2E), nevidí odesílatele (sealed sender), neloguje IP.
//! Zná jen: rotovatelný routing token příjemce, msg_uuid (dedup) a opaque
//! payload. Jediná krypto role: certifikační autorita sealed senderu
//! (vydává SenderCertificate) + ověření XEdDSA podpisu při AUTH.

mod apns;
mod attachments;
mod certs;
mod fcm;
mod net;
mod push;
mod rest;
mod state;
mod turn;
mod ws;

use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;

use axum::extract::DefaultBodyLimit;
use axum::http::StatusCode;
use axum::routing::{delete, get, post};
use axum::serve::ListenerExt;
use axum::Router;
use sqlx::postgres::PgPoolOptions;
use tower_governor::governor::GovernorConfigBuilder;
use tower_governor::GovernorLayer;

use crate::net::{TrustedProxies, TrustedProxyIp};
use tower_http::timeout::TimeoutLayer;
use tracing_subscriber::EnvFilter;

/// Max velikost request body (registrace se 100 OTP klíči má ~15 KB).
const MAX_BODY_BYTES: usize = 64 * 1024;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Log formát bez IP adres a bez identifikátorů klientů — relay nesmí nic z toho uchovávat.
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .init();

    let database_url = std::env::var("DATABASE_URL")
        .unwrap_or_else(|_| "postgres://sepot:sepot_dev@127.0.0.1/sepot_relay".into());
    let bind = std::env::var("SEPOT_BIND").unwrap_or_else(|_| "127.0.0.1:8470".into());

    let pool = PgPoolOptions::new()
        .max_connections(8)
        .connect(&database_url)
        .await?;
    sqlx::migrate!("./migrations").run(&pool).await?;

    let certs = certs::CertAuthority::init(&pool).await?;
    let attachments_cfg = attachments::Config::from_env();
    tokio::fs::create_dir_all(attachments_cfg.dir.join("tmp")).await?;
    // Trusted proxy sada je sdílená mezi WS conn-cap (AppState) a všemi
    // governor limity — jeden zdroj pravdy o tom, komu se věří XFF.
    let trusted = Arc::new(TrustedProxies::from_env());
    let state = Arc::new(state::AppState::new(
        pool,
        certs,
        attachments_cfg,
        trusted.clone(),
    ));
    attachments::spawn_cleanup(state.clone());

    // ── Rate limiting (minimální sada; plný PoW/Privacy Pass později) ──
    //
    // Klíč = klientská IP přes TrustedProxyIp: X-Forwarded-For/X-Real-Ip se
    // uzná JEN od trusted proxy (traefik), jinak peer adresa. Onion klienti
    // přicházejí z tor kontejneru (mimo trusted sadu) → sdílí jeden bucket
    // a nemohou si IP nastavit hlavičkou (SECURITY audit #1).
    // In-memory token bucket — nikdy se nezapisuje na disk (privacy).

    // registrace: zápis do DB bez auth → nejpřísnější (burst 10, +1/5 min)
    let gov_register = Arc::new(
        GovernorConfigBuilder::default()
            .key_extractor(TrustedProxyIp(trusted.clone()))
            .burst_size(10)
            .period(Duration::from_secs(300))
            .finish()
            .expect("governor config"),
    );
    // čtecí API (bundle žere OTP klíče → drain ochrana): burst 60, +2/s
    let gov_general = Arc::new(
        GovernorConfigBuilder::default()
            .key_extractor(TrustedProxyIp(trusted.clone()))
            .burst_size(60)
            .per_second(2)
            .finish()
            .expect("governor config"),
    );

    // přílohy: upload je autentizovaný, ale drahý (disk) → burst 30, +1/s
    let gov_attachments = Arc::new(
        GovernorConfigBuilder::default()
            .key_extractor(TrustedProxyIp(trusted.clone()))
            .burst_size(30)
            .per_second(1)
            .finish()
            .expect("governor config"),
    );

    // Governor drží mapu IP→bucket v paměti — periodicky vyhazovat staré
    for limiter in [
        gov_register.limiter().clone(),
        gov_general.limiter().clone(),
        gov_attachments.limiter().clone(),
    ] {
        tokio::spawn(async move {
            let mut tick = tokio::time::interval(Duration::from_secs(60));
            loop {
                tick.tick().await;
                limiter.retain_recent();
            }
        });
    }

    // Úklid značek budíčků a OTP oken (jen paměť)
    {
        let state = state.clone();
        tokio::spawn(async move {
            let mut tick = tokio::time::interval(Duration::from_secs(600));
            loop {
                tick.tick().await;
                state.prune_marks();
            }
        });
    }

    let register_routes = Router::new()
        .route("/v1/register", post(rest::register))
        .layer(GovernorLayer::new(gov_register));

    let general_routes = Router::new()
        .route("/v1/server-info", get(rest::server_info))
        .route("/v1/keys/{delivery_address}", get(rest::fetch_bundle))
        // doplnění one-time prekeys / rotace signed a Kyber prekey (auth)
        .route("/v1/keys", post(rest::upload_keys))
        .route("/v1/certificate/delivery", get(rest::certificate_delivery))
        .route("/v1/identity", delete(rest::delete_identity))
        .layer(GovernorLayer::new(gov_general));

    let rest_routes = register_routes
        .merge(general_routes)
        .layer(TimeoutLayer::with_status_code(
            StatusCode::REQUEST_TIMEOUT,
            Duration::from_secs(30),
        ));

    // Přílohy: velká těla tečou streamem na disk (strop hlídá handler,
    // DefaultBodyLimit se na raw Body nevztahuje) + delší timeout na
    // pomalé linky (25 MiB přes mobilní síť).
    let attachment_routes = Router::new()
        .route("/v1/attachments", post(attachments::upload))
        .route("/v1/attachments/{blob_id}", get(attachments::download))
        .layer(GovernorLayer::new(gov_attachments))
        .layer(TimeoutLayer::with_status_code(
            StatusCode::REQUEST_TIMEOUT,
            Duration::from_secs(120),
        ));

    let app = Router::new()
        // health bez limitů — interní docker/uptime checky; ready ověří i DB
        .route("/v1/health", get(rest::health))
        .route("/v1/ready", get(rest::ready))
        // WS má vlastní limity (conn cap per IP, auth deadline, frame rate)
        .route("/v1/ws", get(ws::ws_handler))
        .merge(rest_routes)
        .merge(attachment_routes)
        .layer(DefaultBodyLimit::max(MAX_BODY_BYTES))
        .with_state(state.clone());

    raise_nofile_limit();
    tracing::info!(%bind, revision = %state.revision, "sepot-relay startuje");
    let listener = tokio::net::TcpListener::bind(&bind).await?.tap_io(|tcp| {
        // Bez TCP_NODELAY čeká každý další malý zápis na ACK klienta (Nagle
        // × zpožděné ACK = ~40 ms). Nejvíc to bolí hned po AUTH: AUTH_OK a
        // za ním DELIVER z fronty je přesně cesta appky probuzené budíčkem.
        // axum si ho sám nezapne. Selhat to může jen na už zavřeném socketu.
        if let Err(e) = tcp.set_nodelay(true) {
            tracing::debug!("TCP_NODELAY nenastaven: {e}");
        }
    });
    // ConnectInfo: peer adresa pro rate-limit fallback a WS conn cap.
    // Graceful shutdown: SIGTERM od dockeru nechá doběhnout
    // rozjeté uploady; WS klienti se jen přepojí.
    axum::serve(
        listener,
        app.into_make_service_with_connect_info::<SocketAddr>(),
    )
    .with_graceful_shutdown(shutdown_signal())
    .await?;
    Ok(())
}

async fn shutdown_signal() {
    let mut term = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
        .expect("SIGTERM handler");
    tokio::select! {
        _ = term.recv() => {}
        _ = tokio::signal::ctrl_c() => {}
    }
    tracing::info!("sepot-relay končí (signál)");
}

/// Soft limit otevřených souborů na hard limit. Každé WS spojení je jeden
/// deskriptor; docker dává soft 1024 → strop ~1 000 klientů, zatímco hard
/// bývá 2^19. Selhání se jen zaloguje.
fn raise_nofile_limit() {
    let mut lim = libc::rlimit {
        rlim_cur: 0,
        rlim_max: 0,
    };
    // SAFETY: getrlimit/setrlimit jen čtou a zapisují předaný struct.
    unsafe {
        if libc::getrlimit(libc::RLIMIT_NOFILE, &mut lim) != 0 {
            return;
        }
        if lim.rlim_cur < lim.rlim_max {
            lim.rlim_cur = lim.rlim_max;
            if libc::setrlimit(libc::RLIMIT_NOFILE, &lim) != 0 {
                tracing::warn!("RLIMIT_NOFILE se nepodařilo zvednout");
                return;
            }
        }
    }
    tracing::info!(nofile = lim.rlim_cur, "limit otevřených souborů");
}
