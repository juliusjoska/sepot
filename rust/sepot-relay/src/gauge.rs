//! Obsazenost offline fronty: celkem a na příjemce. Jen v paměti.
//!
//! Stropy fronty se dřív vynucovaly mazáním nejstarších obálek po každém
//! vložení (okenní dotaz přes celou frontu příjemce). To bylo drahé a hlavně
//! škodlivé: kdo znal adresu, mohl příjemci frontu přeplnit a tím mu potichu
//! smazat čekající zprávy. Teď se plná fronta odmítá, a aby kontrola nestála
//! dotaz na každou obálku, drží relay naměřené hodnoty chvíli v paměti a mezi
//! měřeními je dopočítává z vlastních vložení a potvrzení.

use std::sync::atomic::{AtomicI64, Ordering};
use std::time::{Duration, Instant};

use dashmap::DashMap;

/// Jak dlouho platí naměřená obsazenost fronty příjemce. Mazání mimo relay
/// (blokace jiným procesem, hodinový úklid prošlých obálek) se projeví
/// nejpozději po téhle době.
const RECIPIENT_GAUGE_TTL: Duration = Duration::from_secs(30);

/// Příděl příjemce se krátí od poloviny globálního stropu.
const PRESSURE_FROM_FRACTION: i64 = 2;
/// Kolikrát menší příděl má příjemce, když je fronta relaye pod tlakem.
const PRESSURE_DIVISOR: i64 = 8;
/// Příděl, který má příjemce i nad globálním stropem: dvě největší obálky
/// a stovka drobných. Kdo si frontu vybírá, ten ji má prázdnou a relay mu
/// doručuje dál, i když útočník zaplnil všechno ostatní.
const FLOOR_BYTES: i64 = 512 * 1024;
const FLOOR_COUNT: i64 = 100;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct QueueUsage {
    pub count: i64,
    pub bytes: i64,
}

/// Strop fronty jednoho příjemce; 0 = daná dimenze bez omezení.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct RecipientCaps {
    pub count: i64,
    pub bytes: i64,
}

impl RecipientCaps {
    /// Vejde se k `usage` ještě obálka o `bytes` bajtech?
    pub fn admits(&self, usage: QueueUsage, bytes: i64) -> bool {
        (self.count == 0 || usage.count < self.count)
            && (self.bytes == 0 || usage.bytes.saturating_add(bytes) <= self.bytes)
    }

    /// Příděl příjemce podle zaplnění celé fronty relaye (`total_cap` 0 =
    /// bez globálního stropu). Globální strop je záměrně měkký: tvrdé
    /// „relay je plný“ by zastavilo doručování všem, a přesně o to útočníkovi
    /// jde. Místo toho se s rostoucím zaplněním krátí, kolik smí čekat na
    /// jednoho příjemce — zaplnit zbytek pak chce řádově víc adres.
    pub fn under_pressure(self, total_bytes: i64, total_cap: i64) -> Self {
        if total_cap == 0 {
            return self;
        }
        let shrink = |value: i64, floor: i64| match value {
            0 => 0,
            value => (value / PRESSURE_DIVISOR).max(floor),
        };
        let limit_to = |value: i64, floor: i64| match value {
            0 => floor,
            value => value.min(floor),
        };
        if total_bytes >= total_cap {
            Self {
                count: limit_to(self.count, FLOOR_COUNT),
                bytes: limit_to(self.bytes, FLOOR_BYTES),
            }
        } else if total_bytes >= total_cap / PRESSURE_FROM_FRACTION {
            Self {
                count: shrink(self.count, FLOOR_COUNT),
                bytes: shrink(self.bytes, FLOOR_BYTES),
            }
        } else {
            self
        }
    }
}

struct Measured {
    usage: QueueUsage,
    at: Instant,
}

/// delivery_address → naposledy naměřená obsazenost fronty.
#[derive(Default)]
pub struct RecipientGauges(DashMap<Vec<u8>, Measured>);

impl RecipientGauges {
    /// Platná hodnota, nebo `None` = je potřeba změřit v DB.
    pub fn get(&self, dst_address: &[u8]) -> Option<QueueUsage> {
        self.0
            .get(dst_address)
            .filter(|measured| measured.at.elapsed() < RECIPIENT_GAUGE_TTL)
            .map(|measured| measured.usage)
    }

    pub fn set(&self, dst_address: &[u8], usage: QueueUsage) {
        self.0.insert(
            dst_address.to_vec(),
            Measured {
                usage,
                at: Instant::now(),
            },
        );
    }

    /// Relay vložil obálku. Bez záznamu není co opravovat, změří se příště.
    pub fn added(&self, dst_address: &[u8], bytes: i64) {
        if let Some(mut measured) = self.0.get_mut(dst_address) {
            measured.usage.count += 1;
            measured.usage.bytes += bytes;
        }
    }

    /// Příjemce obálku potvrdil a relay ji smazal.
    pub fn removed(&self, dst_address: &[u8], bytes: i64) {
        if let Some(mut measured) = self.0.get_mut(dst_address) {
            measured.usage.count = (measured.usage.count - 1).max(0);
            measured.usage.bytes = (measured.usage.bytes - bytes).max(0);
        }
    }

    /// Fronta se změnila jinak než po jedné obálce; příště změřit.
    pub fn forget(&self, dst_address: &[u8]) {
        self.0.remove(dst_address);
    }

    pub fn prune(&self) {
        self.0
            .retain(|_, measured| measured.at.elapsed() < RECIPIENT_GAUGE_TTL);
    }
}

/// Bajty obálek v celé frontě: periodické měření v DB a mezi měřeními
/// vlastní vložení a potvrzení. Mazání mimo relay opraví až další měření,
/// do té doby je hodnota nadsazená — bezpečným směrem.
#[derive(Default)]
pub struct QueueTotal(AtomicI64);

impl QueueTotal {
    pub fn get(&self) -> i64 {
        self.0.load(Ordering::Relaxed)
    }

    pub fn set(&self, bytes: i64) {
        self.0.store(bytes, Ordering::Relaxed);
    }

    pub fn added(&self, bytes: i64) {
        self.0.fetch_add(bytes, Ordering::Relaxed);
    }

    pub fn removed(&self, bytes: i64) {
        // Bez podtečení: potvrzení obálky, kterou poslední měření ještě
        // nevidělo, by jinak počítadlo stáhlo pod nulu.
        let _ = self
            .0
            .fetch_update(Ordering::Relaxed, Ordering::Relaxed, |current| {
                Some((current - bytes).max(0))
            });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const MIB: i64 = 1024 * 1024;
    const NORMAL: RecipientCaps = RecipientCaps {
        count: 10_000,
        bytes: 50 * MIB,
    };
    const TOTAL_CAP: i64 = 2048 * MIB;

    #[test]
    fn plna_fronta_dalsi_obalku_nepusti() {
        let caps = RecipientCaps {
            count: 3,
            bytes: 1000,
        };
        let usage = |count, bytes| QueueUsage { count, bytes };
        assert!(caps.admits(usage(2, 500), 500));
        assert!(!caps.admits(usage(2, 500), 501), "bajty");
        assert!(!caps.admits(usage(3, 0), 1), "počet");
        let unlimited = RecipientCaps { count: 0, bytes: 0 };
        assert!(unlimited.admits(usage(i64::MAX, i64::MAX), i64::MAX));
    }

    #[test]
    fn pridel_prijemce_se_krati_s_tlakem() {
        assert_eq!(NORMAL.under_pressure(TOTAL_CAP / PRESSURE_FROM_FRACTION - 1, TOTAL_CAP), NORMAL);
        assert_eq!(
            NORMAL.under_pressure(TOTAL_CAP / PRESSURE_FROM_FRACTION, TOTAL_CAP),
            RecipientCaps {
                count: 10_000 / PRESSURE_DIVISOR,
                bytes: 50 * MIB / PRESSURE_DIVISOR,
            }
        );
        assert_eq!(
            NORMAL.under_pressure(TOTAL_CAP, TOTAL_CAP),
            RecipientCaps {
                count: FLOOR_COUNT,
                bytes: FLOOR_BYTES,
            },
            "nad stropem zbývá jen zaručený příděl"
        );
        assert_eq!(
            NORMAL.under_pressure(i64::MAX, 0),
            NORMAL,
            "bez globálního stropu se nekrátí"
        );
    }

    /// Zaručený příděl musí pojmout největší obálku, jinak by nad stropem
    /// neprošla ani prázdnou frontou.
    #[test]
    fn zaruceny_pridel_pojme_nejvetsi_obalku() {
        let floor = NORMAL.under_pressure(TOTAL_CAP, TOTAL_CAP);
        let empty = QueueUsage { count: 0, bytes: 0 };
        assert!(floor.admits(empty, 262_144));
    }

    #[test]
    fn tlak_nezvedne_strop_ktery_je_uz_mensi() {
        let small = RecipientCaps {
            count: 10,
            bytes: 1000,
        };
        assert_eq!(small.under_pressure(TOTAL_CAP, TOTAL_CAP), small);
        let unlimited = RecipientCaps { count: 0, bytes: 0 };
        assert_eq!(
            unlimited.under_pressure(TOTAL_CAP, TOTAL_CAP),
            RecipientCaps {
                count: FLOOR_COUNT,
                bytes: FLOOR_BYTES,
            },
            "nad stropem platí příděl i tam, kde strop příjemce jinak není"
        );
    }

    #[test]
    fn meridlo_prijemce_pocita_vlozeni_a_potvrzeni() {
        let gauges = RecipientGauges::default();
        assert_eq!(gauges.get(b"a"), None);
        gauges.added(b"a", 100);
        assert_eq!(gauges.get(b"a"), None, "bez měření se nic neodhaduje");
        gauges.set(b"a", QueueUsage { count: 2, bytes: 300 });
        gauges.added(b"a", 100);
        gauges.removed(b"a", 250);
        assert_eq!(gauges.get(b"a"), Some(QueueUsage { count: 2, bytes: 150 }));
        gauges.removed(b"a", 1000);
        gauges.removed(b"a", 1000);
        gauges.removed(b"a", 1000);
        assert_eq!(gauges.get(b"a"), Some(QueueUsage { count: 0, bytes: 0 }));
        gauges.forget(b"a");
        assert_eq!(gauges.get(b"a"), None);
    }

    #[test]
    fn celkove_meridlo_nepodtece() {
        let total = QueueTotal::default();
        total.set(100);
        total.added(50);
        total.removed(500);
        assert_eq!(total.get(), 0);
    }
}
