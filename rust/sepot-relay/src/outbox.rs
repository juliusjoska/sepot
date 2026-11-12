//! Odchozí fronta jednoho WS spojení s rozpočtem v bajtech.
//!
//! Kanál omezený jen počtem rámců nestačí: rámec má až 256 KiB, takže
//! 64 rámců = 16 MiB na spojení, které ze socketu nečte. Pár desítek
//! takových spojení vyčerpá paměť celého relaye. Fronta proto počítá
//! zakódované bajty a rozpočet drží, dokud writer rámec nezapíše do socketu.

use std::sync::Arc;

use axum::body::Bytes;
use prost::Message;
use sepot_proto::v1;
use tokio::sync::{mpsc, OwnedSemaphorePermit, Semaphore};

/// Kolik zakódovaných bajtů smí čekat na zápis jednomu spojení. Čtyři
/// největší obálky; víc by nečtoucímu klientovi jen drželo paměť, obálky
/// jsou stejně ve frontě v DB.
pub const OUTBOX_MAX_BYTES: usize = 1024 * 1024;
/// Strop počtu čekajících rámců: drobné rámce (doručenky) stojí víc režií
/// než obsahem a bajtový rozpočet by jich pustil desítky tisíc.
const OUTBOX_MAX_FRAMES: usize = 256;

/// Spojení skončilo, rámec už nemá kdo zapsat.
#[derive(Debug, PartialEq, Eq)]
pub struct Closed;

/// Zakódovaný rámec a jeho díl rozpočtu; díl se vrací zahozením.
pub struct Queued {
    pub bytes: Bytes,
    pub permit: OwnedSemaphorePermit,
}

#[derive(Clone)]
pub struct Outbox {
    tx: mpsc::Sender<Queued>,
    budget: Arc<Semaphore>,
}

pub struct OutboxReceiver {
    rx: mpsc::Receiver<Queued>,
    budget: Arc<Semaphore>,
}

/// Konec writeru musí probudit i odesílače čekající na rozpočet, jinak by
/// viseli na semaforu, který už nikdo neuvolní.
impl Drop for OutboxReceiver {
    fn drop(&mut self) {
        self.budget.close();
    }
}

pub fn channel() -> (Outbox, OutboxReceiver) {
    let (tx, rx) = mpsc::channel(OUTBOX_MAX_FRAMES);
    let budget = Arc::new(Semaphore::new(OUTBOX_MAX_BYTES));
    (
        Outbox {
            tx,
            budget: budget.clone(),
        },
        OutboxReceiver { rx, budget },
    )
}

/// Díl rozpočtu pro rámec. Prázdný rámec stojí aspoň bajt, ať ho strop
/// počtu není jediná brzda; větší než celý rozpočet protokol nezná.
fn cost(frame: &v1::ServerFrame) -> u32 {
    frame.encoded_len().clamp(1, OUTBOX_MAX_BYTES) as u32
}

impl Outbox {
    /// Zařadí rámec, jen když se hned vejde. `false` = klient nestíhá číst
    /// (nebo spojení skončilo); volající nečeká a obálku nechá ve frontě DB.
    pub fn try_send(&self, frame: &v1::ServerFrame) -> bool {
        let Ok(permit) = self.budget.clone().try_acquire_many_owned(cost(frame)) else {
            return false;
        };
        let queued = Queued {
            bytes: frame.encode_to_vec().into(),
            permit,
        };
        self.tx.try_send(queued).is_ok()
    }

    /// Zařadí rámec, až na něj bude rozpočet. Čeká jen na vlastní spojení;
    /// volající čekání hlídá odpojením a koncem writeru.
    pub async fn send(&self, frame: &v1::ServerFrame) -> Result<(), Closed> {
        let permit = self
            .budget
            .clone()
            .acquire_many_owned(cost(frame))
            .await
            .map_err(|_| Closed)?;
        let queued = Queued {
            bytes: frame.encode_to_vec().into(),
            permit,
        };
        self.tx.send(queued).await.map_err(|_| Closed)
    }
}

impl OutboxReceiver {
    pub async fn recv(&mut self) -> Option<Queued> {
        self.rx.recv().await
    }

    /// Další rámec bez čekání, už dekódovaný; rozpočet se tím uvolní.
    #[cfg(test)]
    pub fn try_frame(&mut self) -> Option<v1::ServerFrame> {
        let queued = self.rx.try_recv().ok()?;
        Some(v1::ServerFrame::decode(queued.bytes.as_ref()).expect("rámec"))
    }

    #[cfg(test)]
    pub async fn frame(&mut self) -> Option<v1::ServerFrame> {
        let queued = self.rx.recv().await?;
        Some(v1::ServerFrame::decode(queued.bytes.as_ref()).expect("rámec"))
    }
}

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use super::*;

    fn deliver(payload_len: usize) -> v1::ServerFrame {
        v1::ServerFrame {
            frame: Some(v1::server_frame::Frame::Deliver(v1::Envelope {
                payload: vec![0xA5; payload_len],
                ..Default::default()
            })),
        }
    }

    /// Nečtoucí spojení nesmí držet víc než rozpočet, ať je
    /// rámců jakkoli málo.
    #[tokio::test]
    async fn necteny_kanal_drzi_nejvys_rozpocet() {
        let (outbox, _rx) = channel();
        let frame = deliver(200 * 1024);
        let fits = OUTBOX_MAX_BYTES / frame.encoded_len();
        for _ in 0..fits {
            assert!(outbox.try_send(&frame));
        }
        assert!(fits < OUTBOX_MAX_FRAMES, "test má narazit na bajty, ne na počet");
        assert!(!outbox.try_send(&frame), "nad rozpočet se rámec nezařadí");
        assert!(
            tokio::time::timeout(Duration::from_millis(50), outbox.send(&frame))
                .await
                .is_err(),
            "send čeká na místo, nezařadí nad rozpočet"
        );
    }

    #[tokio::test]
    async fn zapsany_ramec_rozpocet_uvolni() {
        let (outbox, mut rx) = channel();
        let frame = deliver(600 * 1024);
        assert!(outbox.try_send(&frame));
        assert!(!outbox.try_send(&frame));
        drop(rx.recv().await.expect("rámec"));
        assert!(outbox.try_send(&frame), "po zápisu je místo zpět");
    }

    #[tokio::test]
    async fn konec_writeru_probudi_cekajici() {
        let (outbox, rx) = channel();
        let frame = deliver(600 * 1024);
        assert!(outbox.try_send(&frame));
        let waiting = tokio::spawn({
            let outbox = outbox.clone();
            async move { outbox.send(&deliver(600 * 1024)).await }
        });
        tokio::task::yield_now().await;
        drop(rx);
        assert_eq!(waiting.await.expect("úloha"), Err(Closed));
        assert!(!outbox.try_send(&frame));
    }

    #[tokio::test]
    async fn strop_poctu_drobnych_ramcu() {
        let (outbox, _rx) = channel();
        let frame = deliver(1);
        for _ in 0..OUTBOX_MAX_FRAMES {
            assert!(outbox.try_send(&frame));
        }
        assert!(!outbox.try_send(&frame));
    }
}
