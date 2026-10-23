# Šepot

**Šepot** is an end-to-end encrypted messenger with anonymous, on-device identity. There is no phone number, e-mail, or password: an account is a keypair generated on the device, your ID is the fingerprint of your public key, and the only backup is a mnemonic phrase.

The design goal is **metadata minimization with a public threat model** — never "zero metadata". The relay is deliberately dumb: it cannot read message content, envelopes carry no sender, and it neither stores a sender–recipient link nor logs IP addresses. What it *does* see while a connection is open is documented honestly below.

> Status: 1.2.x. Android is on [Google Play](https://play.google.com/store/apps/details?id=cz.sepot.sepot); iOS is on the App Store outside the EU, with EU availability pending Apple's trader verification under the Digital Services Act. See [`CHANGELOG.md`](CHANGELOG.md).

## Features

- **End-to-end encryption** via the open-source Rust `libsignal` library: X3DH + post-quantum PQXDH (Kyber-1024) key agreement, Double Ratchet, and sealed sender.
- **Anonymous identity** — no phone/e-mail/password. Recovery through a 24-word mnemonic that encodes the identity key itself (not a KDF seed).
- **Encrypted at rest** — all local data lives in SQLCipher, unlocked by a PIN (Argon2id-derived key) or biometrics. Optional **duress PIN** opens a separate empty database.
- **Group chats** — up to 128 members, pairwise fan-out so every member gets full forward secrecy; groups are not a server-side object and the relay keeps no member list.
- **Attachments** — images and files are encrypted client-side (AES-256-GCM) and uploaded as opaque blobs with a TTL; image metadata (EXIF/GPS) is stripped on send.
- **Disappearing messages**, read receipts (off by default), voice messages, replies, reactions, edits, contact verification (safety numbers).
- **Push with or without Google** — UnifiedPush/ntfy when a distributor is installed, otherwise FCM on Android (default since 1.2.0, can be switched off) and APNs on iOS. A push wake-up never carries content, sender, or count.
- **Tor transport** (Android, via Orbot) — routes relay traffic over a `.onion` to hide the client IP. Off by default.
- **Five languages** — Czech, English, German, Russian, Italian. The UI follows the system language and can be overridden in Settings.

## How it works

```
┌────────────┐   sealed-sender ciphertext    ┌──────────────┐
│  Šepot app │ ───────(WSS or Tor)─────────▶ │  relay       │ ──▶ PostgreSQL
│  (Flutter) │ ◀────── wake push ─────────── │  (Rust/axum) │     (no content,
└────────────┘                               └──────────────┘      no IP, no PII)
     libsignal (FFI)                          offline queue, TTL
     SQLCipher at rest                        opaque attachment blobs
```

Every message is encrypted end-to-end with libsignal and wrapped in a sealed-sender envelope, so the envelope itself carries no sender and the relay routes it by the recipient's delivery address. Undelivered messages sit in a per-recipient queue with a fixed TTL and are hard-deleted on acknowledgement.

**What the relay can see:** the recipient's delivery address, envelope size and timing, push tokens, and — while a connection is open — the client IP address. Envelopes are submitted over an authenticated WebSocket, so at runtime the relay also knows which connected device hands an envelope to which delivery address; it needs that to deliver. **What it does not see or keep:** message content, names, contacts or group membership. It stores no sender–recipient link and no IP addresses, and writes neither to its logs. Someone who took over the relay could start recording runtime metadata; they still could not read messages. See [`SECURITY.md`](SECURITY.md) and the crypto facade `app/lib/core/crypto/`.

**Where data lives:** messages, accounts and keys are stored only on servers in the EU (Hetzner, Germany). Message content never leaves the device unencrypted. Nothing leaves the EU except an anonymous wake-up push via Google (FCM) or Apple (APNs), which carries no message content or sender; the website runs behind Cloudflare.

## Repository layout

| Path | Contents |
|---|---|
| `app/` | Flutter client (Android, iOS; desktop scaffolding present) |
| `rust/` | Cargo workspace — `sepot-relay` (relay server), `sepot-proto` (prost wire types) |
| `proto/` | Protobuf wire definitions — single source for both Rust and Dart |
| `deploy/` | Docker Compose for self-hosting the relay (with an optional Tor onion) |
| `tool/` | Helper scripts (protobuf codegen for Dart) |

## Building

### Client (Android)

```bash
cd app
flutter pub get
flutter build apk --release
```

The native `libsignal` binary is fetched by the Flutter native-assets hook at build time. To point a dev build at your own relay:

```bash
flutter build apk --dart-define=SEPOT_RELAY=http://<dev-relay-host>:8470
```

Release signing reads `app/android/key.properties` (kept out of the repo); without it the build falls back to the debug signing config so `flutter run` still works. FCM is optional — the `google-services` plugin is only applied if you supply your own `app/android/app/google-services.json` (copy `google-services.json.example`). Without it the app runs on UnifiedPush.

### Relay (self-host)

See [`deploy/relay/README.md`](deploy/relay/README.md). The relay is a single Rust binary plus PostgreSQL; put a TLS-terminating reverse proxy in front of it and, optionally, expose it as a Tor onion service.

## Languages

UI strings live in `app/lib/l10n/app_*.arb` (`cs`, `en`, `de`, `ru`, `it`) and are compiled by Flutter's `gen-l10n`. Contributions of new translations are welcome — add an `app_<locale>.arb`, translate the keys from `app_cs.arb`, and run `flutter gen-l10n`.

## Security

Cryptography is implemented by the open-source `libsignal` library, not by hand-rolled primitives. Šepot is not affiliated with Signal Messenger LLC; Signal is a trademark of its owner. The project runs regular internal security audits and penetration tests (August, September and October 2026); no independent third-party audit has taken place yet. If you find a vulnerability, please report it privately to **security@sepot.cz** rather than opening a public issue — see [`SECURITY.md`](SECURITY.md) and [`/.well-known/security.txt`](https://sepot.cz/.well-known/security.txt).

## License

Šepot is licensed under the **GNU Affero General Public License v3.0** — see [`LICENSE`](LICENSE).

The license includes an **AGPL §7 additional permission for app-store distribution**: Šepot may be distributed through App Store / Google Play provided the complete corresponding source stays available under the AGPL through a channel *without* those store restrictions (this repository and the direct APK releases). That permission covers only Šepot's own code. The bundled `libsignal` is AGPL-3.0 held by Signal Messenger, LLC — its app-store status is documented in [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md).
