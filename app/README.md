# Šepot — Flutter client

The Šepot mobile client. See the [repository README](../README.md) for the
project overview, threat model, and license.

## Quick start

```bash
flutter pub get
flutter run                       # against the default relay
flutter build apk --release       # signed release APK (see key.properties)
```

## Layout

| Path | Contents |
|---|---|
| `lib/core/` | Crypto facade, storage (SQLCipher), relay client + transport, push, services |
| `lib/features/` | Screens (onboarding, chat, contacts, groups, settings, safety…) |
| `lib/models/` `lib/providers/` | Data models and Riverpod providers |
| `lib/l10n/` | Localization (`app_*.arb`, generated `AppLocalizations`) |
| `test/` `integration_test/` | Unit, storage, crypto, and on-device integration tests |

## Localization

Strings are defined in `lib/l10n/app_cs.arb` (template) and translated into
`app_en/de/ru/it.arb`. After editing, run `flutter gen-l10n`. See the root
README for how to contribute a new language.
