# Animation plans (2026-09-25 audit)

| # | Title | Sev | Status |
|---|---|---|---|
| 001 | Consolidate springs into NotchAnimations tokens | MED | DONE (verified on-device 2026-09-25) |
| 002 | `page` spring for tab switches | MED | DONE (verified on-device 2026-09-25) |
| 003 | Explicit page-swap transition | MED | DONE (verified on-device 2026-09-25) |
| 004 | Close: one spring, no opacity dip | MED | DONE (verified on-device 2026-09-25) |
| 005 | Lock-screen hide ease-out | MED | DONE (verified on-device 2026-09-25) |
| 006 | Settle Reduce Motion, waveform, parallax | LOW | DONE (verified on-device 2026-09-25) |
| 007 | Missed opportunities (A-D) | LOW | A,B,D done + verified on-device; C blocked (pill lives on voice-sync branch) |

Order: 005, 004, 001, 002, 003, 006, 007 (D last; revert if unstable).
Dependencies: 002 needs 001; 003 needs 002; 007 needs 001.
