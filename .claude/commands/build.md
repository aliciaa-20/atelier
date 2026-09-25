---
description: Build Atelier and relaunch it
---

Build the app and restart the running copy so I can see the change:

1. `pkill -x Atelier` (ignore failure — it may not be running)
2. `xcodebuild -scheme Atelier -configuration Debug build 2>&1 | tail -30`
3. If the build failed, stop and show me the errors. Do not continue.
4. Find the built app:
   `xcodebuild -scheme Atelier -configuration Debug -showBuildSettings 2>/dev/null | grep -m1 " BUILT_PRODUCTS_DIR"`
5. `open "$BUILT_PRODUCTS_DIR/Atelier.app"`
6. Tell me in one line which branch is running (`git branch --show-current`) and what to look at.
