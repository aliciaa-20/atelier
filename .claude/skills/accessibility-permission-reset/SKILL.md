---
name: accessibility-permission-reset
description: Use when volume/brightness keys (or anything else gated on MediaKeyInterceptor's CGEventTap) stop intercepting, or the user reports "granted access but it doesn't work" / "worked before, not now" for Accessibility-gated behavior — a known flakiness where macOS loses track of a rebuilt app's Accessibility grant.
---

# Accessibility Permission Reset

## Overview

`MediaKeyInterceptor`'s `CGEventTap` requires Accessibility permission
(`AXIsProcessTrusted()`). On this project, that permission has repeatedly
appeared "granted" in System Settings while the tap still receives nothing
— root-caused during Phase 8 to **ad-hoc code signing**: every rebuild
re-hashes the binary, and macOS's TCC enforcement for `CGEventTap`
specifically can lose track of a grant across that signature churn, even
though the bundle ID stays constant and the toggle still shows "on."

A toggle off/on in System Settings sometimes appears to fix it (by
coincidence — a subsequent rebuild happened to land on a signature TCC
still recognized), which is why it doesn't reliably work as a fix.

## When to Use

- Volume/brightness keys (or any other Accessibility-gated feature added
  later) stop applying changes or showing the notch HUD.
- The user reports granting access didn't help, or that something that
  worked in a previous session doesn't work now after a rebuild.
- Before spending time re-debugging the interception logic itself (event
  masks, key-code mapping, `MediaKeyMapping`) — rule this out first, since
  it's the far more common cause on this project.

## Procedure

1. **Check the signing identity first.** In `Atelier.xcodeproj/project.pbxproj`,
   confirm `CODE_SIGN_STYLE = Automatic` and a real `DEVELOPMENT_TEAM` (not
   empty). If it's still `CODE_SIGN_IDENTITY = "-"` (ad-hoc), that alone is
   the likely root cause — every rebuild invalidates prior grants by
   design. This should already be fixed (see the "switch to Personal Team
   signing" commit from Phase 8's on-device testing), but confirm rather
   than assume, especially after a merge/rebase that could have reverted it.
2. **Verify the actual running binary's signature**, not just the project
   setting:
   ```sh
   codesign -dvv "$BUILT_PRODUCTS_DIR/Atelier.app" 2>&1 | head -5
   ```
   Look for `TeamIdentifier=<a real ID>`, not `TeamIdentifier=not set` /
   `Signature=adhoc`. If it's ad-hoc, the build itself needs fixing before
   permission will ever stick — see step 1.
3. **Full reset, not a toggle.** A toggle off/on in the Settings UI is
   less reliable than a genuine reset:
   ```sh
   tccutil reset Accessibility com.aliciapereira.Atelier
   ```
4. **Relaunch and grant fresh** via the menu-bar "Grant Accessibility
   Access..." item. `MediaKeyInterceptor` polls for the grant once a
   second after launch (see its `startPollingForPermission`), so this
   should take effect within a couple of seconds without needing a second
   relaunch.
5. **If it still doesn't work** after confirming stable signing + a full
   reset, escalate to systematic debugging of the tap itself (temporary
   `NSLog` in `install()`/`handle()`, as was done live during Phase 8 — see
   that session's transcript for the exact instrumentation used) rather
   than continuing to suspect permission.

## What NOT to Do

- Don't just toggle Accessibility off/on repeatedly hoping it resolves —
  it's not a reliable fix, only `tccutil reset` plus a stable signing
  identity actually is.
- Don't assume the interception *logic* is broken before ruling this out
  — on this project, permission/signing has been the actual cause far more
  often than the event-tap code itself.
- Don't silently rebuild with a still-ad-hoc signing config expecting the
  grant to stick — it structurally can't, by design.
