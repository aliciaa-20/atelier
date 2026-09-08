# ADR 0007 — switch to Personal Team code signing

- **Status:** Accepted
- **Date:** 2026-09-08

## Context

Phase 8's `MediaKeyInterceptor` needs Accessibility permission
(`AXIsProcessTrusted()`) for its `CGEventTap`. Atelier had always used
ad-hoc signing (`CODE_SIGN_IDENTITY = "-"`, `CODE_SIGN_STYLE = Manual`,
no `DEVELOPMENT_TEAM`) — fine for a plain notch overlay with no
TCC-gated capability, since nothing before this depended on macOS
recognizing "this exact binary" as a stable, trusted identity across
rebuilds.

During Phase 8's on-device testing, Accessibility permission repeatedly
appeared *granted* in System Settings while `MediaKeyInterceptor`'s tap
still received nothing — reliably reproduced across a full session of
rebuild → grant → works → rebuild → broken again cycles.

## Investigation

Ad-hoc signing re-hashes the binary on every build (`codesign --sign -`
computes a fresh ad-hoc identity from the binary's own contents each
time). macOS's TCC enforcement for `CGEventTap` specifically appears to
tie a grant to something more specific than just the bundle identifier —
plausibly the code signature/CDHash — so a rebuild can silently
invalidate a prior grant even though the Accessibility list in System
Settings still shows the app toggled on (a stale entry, not a live one).

A toggle off/on in System Settings sometimes appeared to "fix" it, but
this was coincidental — a signature that happened to still be recognized
at that moment, not a real fix, which is why it didn't work reliably.

Confirmed root cause via `security find-identity -v -p codesigning` and
inspecting `TCC.db` directly: the actual fix required both (a) a
*trusted* local certificate (the first attempt hit `CSSMERR_TP_NOT_TRUSTED`
— resolved itself after a keychain trust-chain refresh, likely an OCSP
check completing in the background) and (b) the project's `DEVELOPMENT_TEAM`
set to the correct Team ID — initially set incorrectly to a value pulled
from the certificate's `CN` field (a per-certificate identifier, not the
Team ID), which lives in the certificate's `OU` field instead.

`xcodebuild` from the terminal cannot resolve automatic signing on its
own — it lacks access to Xcode's own Apple ID account session, needed to
create/validate a provisioning identity. A build must be run from Xcode's
GUI at least once (Signing & Capabilities tab, "Automatically manage
signing" + Team selected) before command-line `xcodebuild` builds with
the same settings will succeed.

## Decision

Switch `Atelier.xcodeproj`'s Debug and Release configurations (Atelier
target only, not `AtelierTests` — a bundled test host, not a process that
itself needs Accessibility) to:

- `CODE_SIGN_STYLE = Automatic`
- `CODE_SIGN_IDENTITY = "Apple Development"`
- `DEVELOPMENT_TEAM = <the real Team ID, from the certificate's OU field
  — not the CN field's per-certificate identifier>`

Accepted as a permanent project setting, not a workaround — this pulls
forward part of Phase 16's already-planned "stable signing identity (free
Apple Personal Team)" item, out of necessity for Phase 8 rather than
waiting.

## Consequences

- Accessibility grants now survive rebuilds — confirmed on-device: the
  same grant kept working across multiple subsequent `xcodebuild build`
  cycles without needing `tccutil reset` again.
- The exact Team ID (`2UP2338PJA` at time of writing) is now checked into
  `project.pbxproj`, tied to this developer's specific free Apple
  Developer account — acceptable per this project's own posture (single
  target machine, private repo, per `CLAUDE.md`), but would need
  reconsidering if this repo were ever shared or built on another
  machine/account.
- If Accessibility permission still misbehaves after this: don't
  re-suspect signing first — check `codesign -dvv` on the actual running
  binary to confirm it's really signed with the Personal Team identity
  (not silently reverted to ad-hoc), then follow the
  `accessibility-permission-reset` skill's procedure.
