---
description: Run Atelier's unit test suite
---

Run the test suite and report the result:

1. `xcodebuild test -scheme Atelier -destination 'platform=macOS' 2>&1 | tail -25`
2. If any test failed, show me the failures verbatim. Do not continue.
3. Tell me in one line how many tests passed, and compare it to the count in `README.md` (`grep -n "tests passing" README.md`). If they differ, offer to update the README line (don't edit it silently).
