# Third-party components & license notices

Šepot links third-party components. This file documents their licenses and,
where relevant, their status with respect to app-store distribution.

The cryptographic core is not implemented by Šepot; it is provided by Signal's
`libsignal` through a third-party Dart binding. Both are AGPL-3.0, which is why
their app-store status is documented in detail below.

## Signal `libsignal` (AGPL-3.0)

- **Component:** Signal's Rust `libsignal`, used via FFI behind the
  `SepotCrypto` facade through the `libsignal` Dart binding on pub.dev.
- **Copyright:** Signal Messenger, LLC.
- **License:** GNU Affero General Public License, version 3 (AGPL-3.0).
  Upstream: <https://github.com/signalapp/libsignal>
- **App-store distribution status:** The current AGPL Rust `libsignal` does
  **not** ship with an explicit "app store" additional permission in its
  LICENSE file. However, Signal has publicly stated that it has no objection
  to GPL-compliant open-source applications distributing its libraries through
  the Apple App Store, and it previously added an explicit app-store
  additional permission to the earlier `libsignal-protocol-c`
  (<https://signal.org/blog/license-update/>). Precedent: several
  Signal-derived, GPL/AGPL-licensed messengers (e.g. Session) are distributed
  on the Apple App Store on this basis.

  Šepot relies on that stated position and, as an AGPL work, keeps its
  complete corresponding source available under the AGPL through channels
  without app-store restrictions (this public repository, direct
  APK). A written clarification for the current Rust `libsignal` has been
  requested from Signal (tracking: <https://github.com/signalapp/libsignal/issues/684>).

## `libsignal` Dart binding (AGPL-3.0)

- **Component:** the `libsignal` Dart package on pub.dev, which wraps Signal's
  Rust `libsignal` and ships the precompiled native binaries.
- **License:** AGPL-3.0.
- **App-store distribution status:** in a public issue on the binding's
  repository, its maintainer indicated an intent to add an explicit AGPL §7
  app-store additional permission covering the binding layer and its
  `libsignal_frb` crate, conditioned on the application's complete source being
  publicly available under the AGPL — which this repository provides. That
  permission, once added, would cover only the binding's own code, not Signal's
  upstream `libsignal`.

## Šepot's own App Store exception

Šepot's own code carries an additional permission under AGPL section 7 that
permits app-store distribution (see `LICENSE`). That permission covers only
the parts whose copyright is held by the Šepot contributors; it does not, and
cannot, grant permissions on behalf of Signal Messenger, LLC for `libsignal`.
