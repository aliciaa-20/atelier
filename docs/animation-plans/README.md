# Animation plans (2026-09-25 audit)

| # | Title | Sev | Status |
|---|---|---|---|
| 001 | Consolidate springs into NotchAnimations tokens | MED | TODO |
| 002 | `page` spring for tab switches | MED | TODO |
| 003 | Explicit page-swap transition | MED | TODO |
| 004 | Close: one spring, no opacity dip | MED | TODO |
| 005 | Lock-screen hide ease-out | MED | TODO |
| 006 | Settle Reduce Motion, waveform, parallax | LOW | TODO |
| 007 | Missed opportunities (A-D) | LOW | TODO |

Order: 005, 004, 001, 002, 003, 006, 007 (D last; revert if unstable).
Dependencies: 002 needs 001; 003 needs 002; 007 needs 001.
