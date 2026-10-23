//! Hlídání volného místa na datovém filesystému.
//!
//! Přílohy i DB leží v produkci na jednom filesystému (svazky Dockeru v CT).
//! Když dojde místo, Postgres přestane zapisovat a relay je mrtvý pro všechny
//! — i pro registrace a doručení online. Relay proto přestane přijímat to, co
//! disk plní (přílohy, pak offline fronta) o kus dřív, než místo dojde.

use std::ffi::CString;
use std::path::Path;
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::Arc;
use std::time::Duration;

/// Jak často se místo měří. Zápis 25 MiB přílohy trvá déle než tohle okno,
/// takže práh nepřeskočí ani souběžný nápor.
const MEASURE_EVERY: Duration = Duration::from_secs(5);
/// Pod 20 % volna se do logu zapíše varování (dřív, než zabere kterýkoli
/// práh odmítání), aby si toho Loki alert všiml s předstihem.
const WARN_BELOW_BP: u32 = 2000;

/// Volné místo v setinách procenta; `u32::MAX` = ještě neměřeno / nejde měřit
/// (pak se nic neblokuje — chyba měření nesmí shodit provoz).
pub struct DiskWatch {
    free_bp: AtomicU32,
}

impl DiskWatch {
    pub fn unknown() -> Self {
        Self {
            free_bp: AtomicU32::new(u32::MAX),
        }
    }

    /// Volné místo v procentech, `None` = neznámé.
    pub fn free_pct(&self) -> Option<f64> {
        match self.free_bp.load(Ordering::Relaxed) {
            u32::MAX => None,
            bp => Some(f64::from(bp) / 100.0),
        }
    }

    /// Je volného místa méně než `min_pct`?
    pub fn below(&self, min_pct: f64) -> bool {
        self.free_pct().is_some_and(|free| free < min_pct)
    }

    #[cfg(test)]
    pub fn set_free_pct(&self, pct: f64) {
        self.free_bp.store((pct * 100.0) as u32, Ordering::Relaxed);
    }

    pub fn spawn(self: &Arc<Self>, path: &Path) {
        let watch = self.clone();
        let path = path.to_path_buf();
        tokio::spawn(async move {
            let mut tick = tokio::time::interval(MEASURE_EVERY);
            let mut was_low = false;
            loop {
                tick.tick().await;
                let measured = {
                    let path = path.clone();
                    tokio::task::spawn_blocking(move || free_basis_points(&path))
                        .await
                        .ok()
                        .flatten()
                };
                let Some(bp) = measured else {
                    tracing::warn!("volné místo na disku nejde změřit");
                    continue;
                };
                watch.free_bp.store(bp, Ordering::Relaxed);
                // Změnu stavu zalogovat jednou, ne každých 5 s.
                let low = bp < WARN_BELOW_BP;
                if low != was_low {
                    tracing::warn!(volno_pct = f64::from(bp) / 100.0, "volné místo na disku");
                    was_low = low;
                }
            }
        });
    }
}

/// statvfs: místo dostupné neprivilegovanému procesu (`f_bavail`) vůči
/// velikosti filesystému. Na ZFS s refquota je velikost = kvóta datasetu.
fn free_basis_points(path: &Path) -> Option<u32> {
    let c_path = CString::new(path.as_os_str().as_encoded_bytes()).ok()?;
    // SAFETY: statvfs jen zapisuje do předaného structu, cesta je platný C řetězec.
    let mut st: libc::statvfs = unsafe { std::mem::zeroed() };
    if unsafe { libc::statvfs(c_path.as_ptr(), &mut st) } != 0 || st.f_blocks == 0 {
        return None;
    }
    Some(((st.f_bavail as u128 * 10_000) / st.f_blocks as u128) as u32)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mereni_vrati_rozumne_cislo() {
        let bp = free_basis_points(Path::new("/")).expect("statvfs /");
        assert!(bp <= 10_000);
    }

    #[test]
    fn nezname_misto_nic_neblokuje() {
        let w = DiskWatch::unknown();
        assert!(!w.below(99.0));
        w.set_free_pct(5.0);
        assert!(w.below(8.0));
        assert!(!w.below(4.0));
    }
}
