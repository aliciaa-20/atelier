---
name: liquid-glass
description: Implement Liquid Glass design using .glassEffect() API for iOS/macOS 26+. Covers SwiftUI, AppKit, UIKit, and WidgetKit. Atelier: PARKED until ROADMAP Phase 18 (Liquid Glass notch background); do not load for other work. Use when creating modern glass-based UI effects.
allowed-tools: [Read, Write, Edit, Glob, Grep, AskUserQuestion]
last_verified: 2026-07-16
review_by: 2027-06-22
os_version: iOS 27 / macOS 27
---

> Imported from [rshankras/claude-code-apple-skills](https://github.com/rshankras/claude-code-apple-skills) (MIT license), unmodified.

# Liquid Glass Design

Implement Apple's Liquid Glass design language across all Apple UI frameworks. Covers SwiftUI (`.glassEffect()`), AppKit (`NSGlassEffectView`), UIKit (`UIGlassEffect` + `UIVisualEffectView`), and WidgetKit (rendering modes, accented content, glass elements in widgets).

## When This Skill Activates

- User wants glass/blur effects on views
- User asks about Liquid Glass or modern Apple design
- User needs transparent, interactive UI elements
- User wants morphing transitions between views
- User is implementing glass effects in UIKit with `UIVisualEffectView`
- User needs `UIGlassEffect` or `UIGlassContainerEffect`
- User asks about scroll view edge effects in UIKit
- User wants Liquid Glass in widgets (WidgetKit)
- User needs to support accented rendering mode in widgets
- User asks about widget textures or mounting styles on visionOS

## Design Rules (WWDC25)

Liquid Glass is the material of the **navigation layer** — bars, toolbars, floating controls — never the content layer (tables, lists, rows in a scroll view).

| Rule | Detail |
|------|--------|
| **Never glass on glass** | Don't stack glass. Elements sitting ON glass don't get the material again — style them with fills and vibrancy. |
| **Two variants — never mix them** | **Regular** (default): works at any size, over anything, with adaptive legibility. **Clear**: only when ALL three hold — media-rich content underneath, a dimming layer is acceptable, and bold bright content sits above. Clear has no adaptive behaviors. One variant per interface. |
| **Tint only primary actions** | "When every element is tinted, nothing stands out." |
| **No steady-state intersections** | In resting layouts, content shouldn't sit half-under a glass element — reposition or scale the content instead. |
| **Strip decorated bars** | Remove customized bar backgrounds and borders; build hierarchy through layout and grouping, not decoration. Never group a symbol with a text label in one toolbar group. Action sheets spring from their source element. |

**Scroll edge effects** keep floating elements separated from scrolling content: soft (gradual fade — the iOS default) vs hard (denser, with a dividing line — mostly macOS). One per view edge, and they're not decorative — don't add one where no floating UI elements exist.

**Shape system** — let containers do the math:

| Shape | Radius | Use |
|-------|--------|-----|
| Fixed | Constant | Standalone elements |
| Capsule | Half the element height | Phone-scale controls — add extra margin from the screen edge |
| Concentric | Parent radius minus padding | Nested containers (inner radii auto-calculate); iPad/Mac elements concentric with the window edge |

**Accessibility comes free at the system level**: Reduced Motion decreases lensing and elastic effects; Increased Contrast renders glass elements black/white with a contrasting border. (Lensing is how glass appears — it materializes by modulating how it bends light, and adaptive shadows flip small elements light/dark for legibility over any content.)

## AppKit Implementation

### NSGlassEffectView

```swift
import AppKit

// Create glass effect view
let glassView = NSGlassEffectView(frame: NSRect(x: 20, y: 20, width: 200, height: 100))
glassView.cornerRadius = 16.0
glassView.tintColor = NSColor.systemBlue.withAlphaComponent(0.3)

// Create content
let label = NSTextField(labelWithString: "Glass Content")
label.translatesAutoresizingMaskIntoConstraints = false

// Set content view
glassView.contentView = label

// Add constraints
if let contentView = glassView.contentView {
    NSLayoutConstraint.activate([
        label.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
        label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
    ])
}
```

### NSGlassEffectContainerView

```swift
// Create container
let container = NSGlassEffectContainerView(frame: bounds)
container.spacing = 40.0

// Create content view
let contentView = NSView(frame: container.bounds)
container.contentView = contentView

// Add glass views to content
let glass1 = NSGlassEffectView(frame: NSRect(x: 20, y: 50, width: 150, height: 100))
let glass2 = NSGlassEffectView(frame: NSRect(x: 190, y: 50, width: 150, height: 100))

contentView.addSubview(glass1)
contentView.addSubview(glass2)
```

### Interactive AppKit Glass

```swift
class InteractiveGlassView: NSGlassEffectView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        setupTracking()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTracking()
    }

    private func setupTracking() {
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .activeInActiveApp
        ]
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: options,
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            animator().tintColor = NSColor.systemBlue.withAlphaComponent(0.2)
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            animator().tintColor = nil
        }
    }
}
```


## More detail

SwiftUI quick start, GlassEffectContainer, morphing, button styles, common patterns,
migration from the old API, and UIKit live in `references/swiftui-uikit-patterns.md`.
Read only the section needed (grep its `##` headings first).
