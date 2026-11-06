//! Podpříkazy provozovatele jako skutečný proces: rozhodnutí v `main`
//! padne před migracemi a CA, návratový kód přežije i zavřený stdout.
//! #[ignore] — spouštět s DB: `cargo test -p sepot-relay -- --ignored`.

use std::process::{Command, Stdio};

use rand::RngCore;
use sqlx::PgPool;

/// Stejná vývojová DB jako u testů v crate, když `DATABASE_URL` chybí.
const DEV_DATABASE_URL: &str = "postgres://sepot:sepot_dev@127.0.0.1/sepot_relay";
/// Chyba databáze nebo chybějící schéma (admin.rs).
const EXIT_DB: i32 = 1;
const SCHEMA_MISSING: &str = "Databáze nemá schéma 0005, nic nedělám.\n";

fn database_url() -> String {
    std::env::var("DATABASE_URL").unwrap_or_else(|_| DEV_DATABASE_URL.into())
}

/// Prázdné schéma; podpříkaz ho dostane jako jediné na `search_path`.
struct EmptySchema {
    admin: PgPool,
    name: String,
}

impl EmptySchema {
    async fn new() -> Self {
        let mut suffix = [0u8; 6];
        rand::rng().fill_bytes(&mut suffix);
        let name = format!("test_proces_{}", hex::encode(suffix));
        let admin = PgPool::connect(&database_url())
            .await
            .expect("testovací DB");
        sqlx::query(&format!("CREATE SCHEMA {name}"))
            .execute(&admin)
            .await
            .expect("schéma");
        Self { admin, name }
    }

    /// URL pro proces: `options` nastaví `search_path` na prázdné schéma.
    fn url(&self) -> String {
        let separator = if database_url().contains('?') {
            '&'
        } else {
            '?'
        };
        format!(
            "{}{separator}options=-c%20search_path%3D{}",
            database_url(),
            self.name
        )
    }

    async fn tables(&self) -> i64 {
        sqlx::query_scalar("SELECT count(*) FROM information_schema.tables WHERE table_schema = $1")
            .bind(&self.name)
            .fetch_one(&self.admin)
            .await
            .expect("počet tabulek")
    }

    async fn remove(self) {
        sqlx::query(&format!("DROP SCHEMA {} CASCADE", self.name))
            .execute(&self.admin)
            .await
            .expect("úklid schématu");
        self.admin.close().await;
    }
}

fn relay(schema: &EmptySchema, command: &str) -> Command {
    let mut process = Command::new(env!("CARGO_BIN_EXE_sepot-relay"));
    process
        .arg(command)
        .env("DATABASE_URL", schema.url())
        .stdin(Stdio::null())
        .stderr(Stdio::piped());
    process
}

#[tokio::test]
#[ignore = "vyžaduje běžící Postgres (dev DB)"]
async fn podprikaz_na_prazdne_db_skonci_1_a_nic_nevytvori() {
    let schema = EmptySchema::new().await;
    for command in ["stav", "seznam"] {
        let output = relay(&schema, command)
            .stdout(Stdio::piped())
            .output()
            .expect("proces");
        assert_eq!(output.status.code(), Some(EXIT_DB), "{command}");
        assert_eq!(String::from_utf8_lossy(&output.stdout), SCHEMA_MISSING);
    }
    assert_eq!(schema.tables().await, 0, "žádné migrace ani klíče CA");
    schema.remove().await;
}

#[tokio::test]
#[ignore = "vyžaduje běžící Postgres (dev DB)"]
async fn zavreny_stdout_neprebije_navratovy_kod() {
    let schema = EmptySchema::new().await;
    let mut child = relay(&schema, "stav")
        .stdout(Stdio::piped())
        .spawn()
        .expect("proces");
    // Čtecí konec roury zavřený dřív, než proces stihne psát (nejdřív se
    // připojí k DB): zápis skončí EPIPE.
    drop(child.stdout.take());
    let output = child.wait_with_output().expect("proces");
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert_eq!(output.status.code(), Some(EXIT_DB), "{stderr}");
    assert!(!stderr.contains("panicked"), "{stderr}");
    schema.remove().await;
}
