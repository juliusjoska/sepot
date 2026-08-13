//! Certifikační autorita sealed senderu (server-signed).
//!
//! Relay drží dlouhodobý server keypair certifikovaný trust rootem a vydává
//! klientům krátkodobé SenderCertificate. Klienti mají trust root pinnutý.

use libsignal_protocol::{
    DeviceId, KeyPair, PrivateKey, PublicKey, SenderCertificate, ServerCertificate, Timestamp,
};
use sqlx::PgPool;

/// Platnost vydaného SenderCertificate (~7 dní).
pub const SENDER_CERT_VALIDITY_MS: u64 = 7 * 24 * 3600 * 1000;

pub struct CertAuthority {
    pub trust_root_public: Vec<u8>,
    server_private: PrivateKey,
    server_certificate: Vec<u8>,
}

impl CertAuthority {
    /// Načte klíče z DB; při prvním startu je vygeneruje a uloží.
    ///
    /// BEZPEČNOST (SECURITY audit #2): trust root private se do DB NEUKLÁDÁ.
    /// Runtime ho nepotřebuje (podpis SenderCertificate dělá server_private),
    /// slouží jen k jednorázovému podpisu server certifikátu při bootstrapu
    /// a hned se zahodí. Kompromitace DB tak neprozradí kotvu důvěry, kterou
    /// klienti pinnují.
    ///
    /// ZBYTKOVÉ RIZIKO: server_private v DB zůstat MUSÍ (runtime podepisování)
    /// a sám stačí na výrobu platného SenderCertificate → kompromitace DB
    /// stále dovolí dočasnou impersonaci. Plné řešení = server keypair do
    /// KMS/HSM, mimo scope kostry. Rotace server klíče vyžaduje offline trust
    /// root (v dev se regeneruje celá kotva → mění se i pin klientů).
    pub async fn init(pool: &PgPool) -> anyhow::Result<Self> {
        let row: Option<(Vec<u8>, Vec<u8>, Vec<u8>)> = sqlx::query_as(
            "SELECT trust_root_public, server_private, server_certificate FROM relay_keys WHERE id = 1",
        )
        .fetch_optional(pool)
        .await?;

        if let Some((trust_root_public, server_private, server_certificate)) = row {
            return Ok(Self {
                trust_root_public,
                server_private: PrivateKey::deserialize(&server_private)
                    .map_err(|e| anyhow::anyhow!("server_private: {e}"))?,
                server_certificate,
            });
        }

        let mut rng = rand::rng();
        let trust_root = KeyPair::generate(&mut rng);
        let server = KeyPair::generate(&mut rng);
        let server_cert = ServerCertificate::new(
            1,
            server.public_key,
            &trust_root.private_key,
            &mut rng,
        )
        .map_err(|e| anyhow::anyhow!("ServerCertificate: {e}"))?;
        let server_cert_bytes = server_cert
            .serialized()
            .map_err(|e| anyhow::anyhow!("serialized: {e}"))?
            .to_vec();

        // trust_root_private se ZÁMĚRNĚ neukládá (audit #2) — sloupec zůstane
        // NULL, private klíč kotvy důvěry žije jen po dobu tohoto bootstrapu.
        sqlx::query(
            "INSERT INTO relay_keys
               (id, trust_root_public, server_public, server_private, server_certificate)
             VALUES (1, $1, $2, $3, $4)",
        )
        .bind(trust_root.public_key.serialize().to_vec())
        .bind(server.public_key.serialize().to_vec())
        .bind(server.private_key.serialize())
        .bind(&server_cert_bytes)
        .execute(pool)
        .await?;

        tracing::info!("vygenerován nový trust root + server certificate (root private nezachován)");
        Ok(Self {
            trust_root_public: trust_root.public_key.serialize().to_vec(),
            server_private: server.private_key,
            server_certificate: server_cert_bytes,
        })
    }

    /// Vydá SenderCertificate pro autentizované zařízení.
    /// `sender_uuid` = hex(account_id) — interní routing handle, NE fingerprint.
    pub fn issue(
        &self,
        sender_uuid: &str,
        device_id: u32,
        identity_key: &[u8],
        now_ms: u64,
    ) -> anyhow::Result<(Vec<u8>, u64)> {
        let expiration = now_ms + SENDER_CERT_VALIDITY_MS;
        let mut rng = rand::rng();
        let cert = SenderCertificate::new(
            sender_uuid.to_string(),
            None,
            PublicKey::deserialize(identity_key)
                .map_err(|e| anyhow::anyhow!("identity_key: {e}"))?,
            DeviceId::try_from(device_id).map_err(|e| anyhow::anyhow!("device_id: {e}"))?,
            Timestamp::from_epoch_millis(expiration),
            ServerCertificate::deserialize(&self.server_certificate)
                .map_err(|e| anyhow::anyhow!("server_certificate: {e}"))?,
            &self.server_private,
            &mut rng,
        )
        .map_err(|e| anyhow::anyhow!("SenderCertificate: {e}"))?;
        let bytes = cert
            .serialized()
            .map_err(|e| anyhow::anyhow!("serialized: {e}"))?
            .to_vec();
        Ok((bytes, expiration))
    }
}
