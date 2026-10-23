//! Kvóty na účet — jen v paměti, nikam se neukládají ani nelogují.
//!
//! Proč v paměti: relay záměrně nikde nedrží vazbu „účet → co poslal / jakou
//! přílohu nahrál“ (metadata). Cena: restart relaye kvóty vynuluje. Proti
//! zaplnění disku proto stojí ještě globální strop příloh a hlídání volného
//! místa (`disk.rs`), které restart nevynuluje.

use std::collections::VecDeque;
use std::time::{Duration, Instant};

use dashmap::DashMap;

/// Token bucket počtu i bajtů na klíč: plný na `count`/`bytes`, za `period`
/// se doplní celý. 0 = daná dimenze bez omezení.
pub struct Budgets {
    count: u64,
    bytes: u64,
    period: Duration,
    map: DashMap<Vec<u8>, Bucket>,
}

struct Bucket {
    count: f64,
    bytes: f64,
    last: Instant,
}

impl Budgets {
    pub fn new(count: u64, bytes: u64, period: Duration) -> Self {
        Self {
            count,
            bytes,
            period,
            map: DashMap::new(),
        }
    }

    fn refill(&self, b: &mut Bucket, now: Instant) {
        let share = now.duration_since(b.last).as_secs_f64() / self.period.as_secs_f64();
        b.count = (b.count + share * self.count as f64).min(self.count as f64);
        b.bytes = (b.bytes + share * self.bytes as f64).min(self.bytes as f64);
        b.last = now;
    }

    /// Odečte jednu položku o `bytes` bajtech; `false` = kvóta vyčerpaná
    /// (nic se neodečte).
    pub fn try_take(&self, key: &[u8], bytes: u64) -> bool {
        self.try_take_at(key, bytes, Instant::now())
    }

    fn try_take_at(&self, key: &[u8], bytes: u64, now: Instant) -> bool {
        let mut b = self.map.entry(key.to_vec()).or_insert_with(|| Bucket {
            count: self.count as f64,
            bytes: self.bytes as f64,
            last: now,
        });
        self.refill(&mut b, now);
        let count_ok = self.count == 0 || b.count >= 1.0;
        let bytes_ok = self.bytes == 0 || b.bytes >= bytes as f64;
        if !(count_ok && bytes_ok) {
            return false;
        }
        b.count -= 1.0;
        b.bytes -= bytes as f64;
        true
    }

    /// Vrátí bajty, které se nakonec nespotřebovaly (upload menší než
    /// rezervace, chyba zápisu).
    pub fn refund(&self, key: &[u8], bytes: u64) {
        if let Some(mut b) = self.map.get_mut(key) {
            b.bytes = (b.bytes + bytes as f64).min(self.bytes as f64);
        }
    }

    /// Úklid plných bucketů (účet dlouho nic neposlal) — paměť jen pro aktivní.
    pub fn prune(&self) {
        let now = Instant::now();
        self.map.retain(|_, b| {
            let share = now.duration_since(b.last).as_secs_f64() / self.period.as_secs_f64();
            share < 1.0
        });
    }
}

/// Kolik bajtů má účet právě uložených (příloh v rámci TTL). Účetnictví po
/// dnech: na účet nejvýš `ttl_days` čísel, ne seznam blobů — paměť je pevná
/// a vazba na jednotlivé bloby nevzniká.
pub struct StoredLedger {
    cap: u64,
    ttl_days: i64,
    map: DashMap<Vec<u8>, VecDeque<(i64, u64)>>,
}

impl StoredLedger {
    pub fn new(cap: u64, ttl_days: i64) -> Self {
        Self {
            cap,
            ttl_days,
            map: DashMap::new(),
        }
    }

    fn today() -> i64 {
        chrono::Utc::now().timestamp().div_euclid(86_400)
    }

    /// Zarezervuje `bytes`; `false` = účet by přesáhl strop uloženého.
    pub fn try_reserve(&self, key: &[u8], bytes: u64) -> bool {
        self.try_reserve_on(key, bytes, Self::today())
    }

    fn try_reserve_on(&self, key: &[u8], bytes: u64, day: i64) -> bool {
        if self.cap == 0 {
            return true;
        }
        let mut days = self.map.entry(key.to_vec()).or_default();
        // Den nahrání + TTL dní: pak je blob úklidem pryč (zaokrouhleno nahoru).
        while days.front().is_some_and(|(d, _)| *d + self.ttl_days < day) {
            days.pop_front();
        }
        let used: u64 = days.iter().map(|(_, b)| b).sum();
        if used.saturating_add(bytes) > self.cap {
            return false;
        }
        match days.back_mut() {
            Some((d, b)) if *d == day => *b += bytes,
            _ => days.push_back((day, bytes)),
        }
        true
    }

    pub fn release(&self, key: &[u8], bytes: u64) {
        if let Some(mut days) = self.map.get_mut(key) {
            if let Some((_, b)) = days.back_mut() {
                *b = b.saturating_sub(bytes);
            }
        }
    }

    pub fn prune(&self) {
        let horizon = Self::today() - self.ttl_days;
        self.map
            .retain(|_, days| days.back().is_some_and(|(d, _)| *d >= horizon));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn budget_odmitne_nad_bajty_i_kusy_a_doplni_se() {
        let q = Budgets::new(3, 1000, Duration::from_secs(3600));
        let t0 = Instant::now();
        assert!(q.try_take_at(b"a", 600, t0));
        assert!(!q.try_take_at(b"a", 600, t0), "bajty došly");
        assert!(q.try_take_at(b"a", 100, t0));
        assert!(q.try_take_at(b"a", 100, t0));
        assert!(!q.try_take_at(b"a", 1, t0), "kusy došly");
        assert!(q.try_take_at(b"b", 600, t0), "jiný účet má vlastní kvótu");
        // za půl periody se doplní polovina
        let t1 = t0 + Duration::from_secs(1800);
        assert!(q.try_take_at(b"a", 400, t1));
    }

    #[test]
    fn budget_nula_znamena_bez_omezeni() {
        let q = Budgets::new(0, 0, Duration::from_secs(1));
        for _ in 0..1000 {
            assert!(q.try_take(b"a", u64::MAX / 2));
        }
    }

    #[test]
    fn refund_vrati_nespotrebovane() {
        let q = Budgets::new(0, 1000, Duration::from_secs(3600));
        assert!(q.try_take(b"a", 1000));
        q.refund(b"a", 700);
        assert!(q.try_take(b"a", 700));
    }

    #[test]
    fn ledger_drzi_strop_a_stare_dny_uvolni() {
        let l = StoredLedger::new(1000, 30);
        assert!(l.try_reserve_on(b"a", 800, 100));
        assert!(!l.try_reserve_on(b"a", 300, 100));
        assert!(l.try_reserve_on(b"b", 300, 100), "jiný účet");
        l.release(b"a", 500);
        assert!(l.try_reserve_on(b"a", 600, 101));
        // po TTL dnech od nahrání je místo zase volné
        assert!(l.try_reserve_on(b"a", 1000, 132));
    }
}
