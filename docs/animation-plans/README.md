# Animation plans (2026-09-25 audit)

| # | Title | Sev | Status |
|---|---|---|---|
| 001 | Consolidate springs into NotchAnimations tokens | MED | DONE (unverified on-device) |
| 002 | `page` spring for tab switches | MED | DONE (unverified on-device) |
| 003 | Explicit page-swap transition | MED | DONE (unverified on-device) |
| 004 | Close: one spring, no opacity dip | MED | DONE (unverified on-device) |
| 005 | Lock-screen hide ease-out | MED | DONE (unverified on-device) |
| 006 | Settle Reduce Motion, waveform, parallax | LOW | DONE (unverified on-device) |
| 007 | Missed opportunities (A-D) | LOW | A,B,D done; C blocked (pill lives on voice-sync branch) |

Order: 005, 004, 001, 002, 003, 006, 007 (D last; revert if unstable).
Dependencies: 002 needs 001; 003 needs 002; 007 needs 001.
