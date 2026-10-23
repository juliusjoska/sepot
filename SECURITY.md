# Security policy

## Reporting a vulnerability

Please report security issues privately — do not open a public issue.

- E-mail: **security@sepot.cz**
- Web form and policy: <https://sepot.cz/zodpovedne-hlaseni>
- Machine-readable contact: <https://sepot.cz/.well-known/security.txt>

You will get an acknowledgement within 72 hours and a status update at least
every 14 days until the issue is resolved. We aim to ship a fix within 30 days
for issues that affect message confidentiality, authentication, or the relay's
metadata guarantees, and we credit reporters in the changelog unless they
prefer otherwise.

## Scope

- the Flutter client (`app/`), including the Signal protocol integration,
  local storage (SQLCipher, PIN/biometrics, duress session) and calls;
- the relay (`rust/sepot-relay/`): authentication, routing, push wake-ups,
  attachments, rate limiting, TURN credentials;
- the public relay at `relay.sepot.cz` and the website `sepot.cz`.

Please do not run denial-of-service tests, mass registrations or scans
against the public relay; a local instance (`deploy/relay/`) is enough to
reproduce almost everything.

## What the relay can and cannot see

The threat model is documented in the README. In short: envelopes carry no
sender (sealed sender) and the relay never sees content. It does see routing
tokens, envelope sizes, timing and push tokens, and while a connection is
open the client IP and which authenticated device submits an envelope to
which delivery address. It stores no sender–recipient link and no IP
addresses. Reports that demonstrate the relay learning or keeping more than
that are the ones we care about most.

## Audits

We run regular internal security audits and penetration tests (August,
September and October 2026); fixes are listed in `CHANGELOG.md`. No
independent third-party audit has taken place yet.
