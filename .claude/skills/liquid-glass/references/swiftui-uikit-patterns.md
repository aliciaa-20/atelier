# Liquid Glass reference: SwiftUI, patterns, migration, UIKit

Moved out of SKILL.md to keep it short. Read only the section you need.

## Quick Start (SwiftUI)

### Basic Glass Effect

```swift
import SwiftUI

Text("Hello, World!")
    .font(.title)
    .padding()
    .glassEffect()  // Capsule shape by default
```

### Custom Shape

```swift
Text("Hello")
    .padding()
    .glassEffect(in: .rect(cornerRadius: 16))

// Available shapes:
// .capsule (default)
// .rect(cornerRadius: CGFloat)
// .rect(corner: .containerConcentric) — radius derived from the container, keeps nested shapes concentric
// .circle
```

### Interactive Glass

```swift
Button("Tap Me") {
    // action
}
.padding()
.glassEffect(.regular.interactive())
```

### Tinted Glass

```swift
Text("Important")
    .padding()
    .glassEffect(.regular.tint(.blue))
```

## Glass Configuration Options

| Option | Description | Example |
|--------|-------------|---------|
| `.regular` | Standard glass effect | `.glassEffect(.regular)` |
| `.tint(Color)` | Add color tint | `.glassEffect(.regular.tint(.orange))` |
| `.interactive()` | Scale, bounce, and shimmer on touch/hover | `.glassEffect(.regular.interactive())` |

## Multiple Glass Effects

### GlassEffectContainer

When using multiple glass elements, wrap them in `GlassEffectContainer` for:
- Better rendering performance
- Proper blending between effects
- Morphing transitions

This is correctness, not just performance: glass can not sample other glass, so nearby glass elements must share ONE container to render and blend correctly.

```swift
GlassEffectContainer(spacing: 40.0) {
    HStack(spacing: 40.0) {
        Image(systemName: "star.fill")
            .frame(width: 80, height: 80)
            .font(.system(size: 36))
            .glassEffect()

        Image(systemName: "heart.fill")
            .frame(width: 80, height: 80)
            .font(.system(size: 36))
            .glassEffect()
    }
}
```

**Spacing Parameter:**
- Controls when effects merge
- Smaller spacing = views must be closer to merge
- Larger spacing = effects merge at greater distances

### Uniting Glass Effects

Combine views into a single glass effect using `glassEffectUnion`:

```swift
@Namespace private var namespace

GlassEffectContainer(spacing: 20.0) {
    HStack(spacing: 20.0) {
        ForEach(items.indices, id: \.self) { index in
            Image(systemName: items[index])
                .frame(width: 60, height: 60)
                .glassEffect()
                .glassEffectUnion(
                    id: index < 2 ? "group1" : "group2",
                    namespace: namespace
                )
        }
    }
}
```

## Morphing Transitions

Create fluid morphing effects when views appear/disappear.

### Setup

1. Create a namespace
2. Assign glass effect IDs
3. Use animations on state changes

```swift
struct MorphingToolbar: View {
    @State private var isExpanded = false
    @Namespace private var namespace

    var body: some View {
        GlassEffectContainer(spacing: 40.0) {
            HStack(spacing: 40.0) {
                // Always visible
                Image(systemName: "pencil")
                    .frame(width: 60, height: 60)
                    .glassEffect()
                    .glassEffectID("pencil", in: namespace)

                // Conditionally visible - will morph in/out
                if isExpanded {
                    Image(systemName: "eraser")
                        .frame(width: 60, height: 60)
                        .glassEffect()
                        .glassEffectID("eraser", in: namespace)

                    Image(systemName: "ruler")
                        .frame(width: 60, height: 60)
                        .glassEffect()
                        .glassEffectID("ruler", in: namespace)
                }
            }
        }

        Button("Toggle") {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
        }
        .buttonStyle(.glass)
    }
}
```

## Button Styles

### Glass Button

```swift
Button("Standard") {
    // action
}
.buttonStyle(.glass)
```

### Glass Prominent Button

```swift
Button("Primary Action") {
    // action
}
.buttonStyle(.glassProminent)
```

## Advanced Techniques

### Background Extension

Extend a hero image beyond the safe area — the system mirrors and blurs it under bars and sidebars:

```swift
Image("hero")
    .backgroundExtensionEffect()
```

Or stretch content under sidebar or inspector:

```swift
NavigationSplitView {
    SidebarView()
} detail: {
    DetailView()
        .background {
            Image("wallpaper")
                .resizable()
                .ignoresSafeArea()
        }
}
```

### Horizontal Scroll Under Sidebar

```swift
ScrollView(.horizontal) {
    HStack {
        ForEach(items) { item in
            ItemView(item: item)
        }
    }
}
.scrollExtensionMode(.underSidebar)
```

### Tab Bar Behaviors

```swift
TabView {
    // tabs
}
.tabBarMinimizeBehavior(.onScrollDown)  // Tab bar recedes while scrolling content
.tabViewBottomAccessory {               // Persistent control docked above the tab bar
    MiniPlayerView()
}
```

### Toolbar Spacers

Split toolbar items into separate glass groups instead of customizing bar backgrounds:

```swift
.toolbar {
    ToolbarItem { editButton }
    ToolbarSpacer(.fixed)      // Visual break — starts a new glass group
    ToolbarItem { shareButton }
    ToolbarSpacer(.flexible)   // Pushes the following group apart
    ToolbarItem { doneButton }
}
```

### Scroll Edge Effect Style

```swift
ScrollView { content }
    .scrollEdgeEffectStyle(.hard, for: .top)  // Hard style for dense UI, mostly macOS
```

### Sheets

Remove custom `presentationBackground` modifiers — they interfere with the sheet's glass material and its morphing behavior.

## Common Patterns

### Floating Action Bar

```swift
struct FloatingActionBar: View {
    @Namespace private var namespace

    var body: some View {
        GlassEffectContainer(spacing: 20) {
            HStack(spacing: 16) {
                ForEach(actions) { action in
                    Button {
                        action.perform()
                    } label: {
                        Image(systemName: action.icon)
                            .font(.title2)
                    }
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive())
                    .glassEffectID(action.id, in: namespace)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }
}
```

### Card with Glass Effect

For a card floating above content (e.g. overlaid on a map). Cards inside a scrolling list are content-layer — don't use glass there. Note the icon uses a fill, not a second `glassEffect`: elements on glass never get glass again.

```swift
struct GlassCard: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title)
                .frame(width: 50, height: 50)
                .background(.blue.opacity(0.15), in: .rect(cornerRadius: 12))

            VStack(alignment: .leading) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .glassEffect(in: .rect(cornerRadius: 16))
    }
}
```

### Tab Bar with Morphing

```swift
struct GlassTabBar: View {
    @Binding var selection: Int
    @Namespace private var namespace

    let tabs = [
        ("house", "Home"),
        ("magnifyingglass", "Search"),
        ("person", "Profile")
    ]

    var body: some View {
        GlassEffectContainer(spacing: 30) {
            HStack(spacing: 30) {
                ForEach(tabs.indices, id: \.self) { index in
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            selection = index
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tabs[index].0)
                                .font(.title2)
                            Text(tabs[index].1)
                                .font(.caption)
                        }
                        .frame(width: 70, height: 60)
                    }
                    .glassEffect(
                        selection == index
                            ? .regular.tint(.blue).interactive()
                            : .regular.interactive()
                    )
                    .glassEffectID("tab\(index)", in: namespace)
                }
            }
        }
    }
}
```

## Migration from Old API

### Before (Old Approach)

```swift
// Old: Using materials directly
VStack {
    Text("Content")
}
.padding()
.background(.ultraThinMaterial)
.cornerRadius(16)
```

### After (New API)

```swift
// New: Using glassEffect modifier
VStack {
    Text("Content")
}
.padding()
.glassEffect(in: .rect(cornerRadius: 16))
```

### Key Differences

| Old Approach | New API |
|--------------|---------|
| `.background(.material)` | `.glassEffect()` |
| Manual corner radius | Shape parameter |
| No interactivity | `.interactive()` modifier |
| Manual tinting | `.tint(Color)` modifier |
| No morphing | `glassEffectID` + `@Namespace` |
| No container grouping | `GlassEffectContainer` |

## UIKit Implementation

### UIGlassEffect

Use `UIVisualEffectView` with a `UIGlassEffect` to create glass surfaces in UIKit:

```swift
import UIKit

let glassEffect = UIGlassEffect()
let visualEffectView = UIVisualEffectView(effect: glassEffect)
visualEffectView.frame = CGRect(x: 50, y: 100, width: 300, height: 200)
visualEffectView.layer.cornerRadius = 20
visualEffectView.clipsToBounds = true

let label = UILabel()
label.text = "Liquid Glass"
label.textAlignment = .center
label.frame = visualEffectView.bounds
visualEffectView.contentView.addSubview(label)
view.addSubview(visualEffectView)
```

#### Customizing the Glass Effect

```swift
glassEffect.tintColor = UIColor.systemBlue.withAlphaComponent(0.3)
glassEffect.isInteractive = true
```

### Interactive Glass in UIKit

Set `isInteractive = true` on a `UIGlassEffect` to make it respond to touch:

```swift
let interactiveGlassEffect = UIGlassEffect()
interactiveGlassEffect.isInteractive = true

let glassButton = UIButton(frame: CGRect(x: 50, y: 300, width: 200, height: 50))
glassButton.setTitle("Glass Button", for: .normal)
glassButton.setTitleColor(.white, for: .normal)

let buttonEffectView = UIVisualEffectView(effect: interactiveGlassEffect)
buttonEffectView.frame = glassButton.bounds
buttonEffectView.layer.cornerRadius = 15
buttonEffectView.clipsToBounds = true

glassButton.insertSubview(buttonEffectView, at: 0)
view.addSubview(glassButton)
```

### UIGlassContainerEffect

Use `UIGlassContainerEffect` when combining multiple glass elements. This is the UIKit equivalent of SwiftUI's `GlassEffectContainer` -- it enables proper blending and morphing between glass views:

```swift
let containerEffect = UIGlassContainerEffect()
containerEffect.spacing = 40.0

let containerView = UIVisualEffectView(effect: containerEffect)
containerView.frame = CGRect(x: 50, y: 400, width: 300, height: 200)

let firstGlassEffect = UIGlassEffect()
let firstGlassView = UIVisualEffectView(effect: firstGlassEffect)
firstGlassView.frame = CGRect(x: 20, y: 20, width: 100, height: 100)
firstGlassView.layer.cornerRadius = 20
firstGlassView.clipsToBounds = true

let secondGlassEffect = UIGlassEffect()
secondGlassEffect.tintColor = UIColor.systemPink.withAlphaComponent(0.3)
let secondGlassView = UIVisualEffectView(effect: secondGlassEffect)
secondGlassView.frame = CGRect(x: 80, y: 60, width: 100, height: 100)
secondGlassView.layer.cornerRadius = 20
secondGlassView.clipsToBounds = true

containerView.contentView.addSubview(firstGlassView)
containerView.contentView.addSubview(secondGlassView)
view.addSubview(containerView)
```

### Scroll View Edge Effects

UIKit scroll views now support configurable edge effects for Liquid Glass integration:

```swift
let scrollView = UIScrollView(frame: view.bounds)
scrollView.topEdgeEffect.style = .automatic
scrollView.bottomEdgeEffect.style = .hard
scrollView.leftEdgeEffect.isHidden = true
scrollView.rightEdgeEffect.isHidden = true
```

**Available Edge Effect Styles:**

| Style | Description |
|-------|-------------|
| `.automatic` | System determines style based on context |
| `.hard` | Hard cutoff with a dividing line |

### UIScrollEdgeElementContainerInteraction

Coordinates glass elements (such as bottom toolbars) with scroll edge behavior:

```swift
let interaction = UIScrollEdgeElementContainerInteraction()
interaction.scrollView = scrollView
interaction.edge = .bottom
buttonContainer.addInteraction(interaction)
```

### Toolbar Integration

UIKit navigation bar items integrate with Liquid Glass automatically; `hidesSharedBackground` opts an item out of the shared glass bar:

```swift
let shareButton = UIBarButtonItem(
    barButtonSystemItem: .action,
    target: self,
    action: #selector(shareAction)
)
let favoriteButton = UIBarButtonItem(
    image: UIImage(systemName: "heart"),
    style: .plain,
    target: self,
    action: #selector(favoriteAction)
)
favoriteButton.hidesSharedBackground = true
navigationItem.rightBarButtonItems = [shareButton, favoriteButton]
```

### UIKit vs SwiftUI Comparison

| SwiftUI | UIKit |
|---------|-------|
| `.glassEffect()` | `UIVisualEffectView(effect: UIGlassEffect())` |
| `.glassEffect(.regular.interactive())` | `UIGlassEffect()` with `isInteractive = true` |
| `.glassEffect(.regular.tint(.blue))` | `UIGlassEffect()` with `tintColor = ...` |
| `GlassEffectContainer(spacing:)` | `UIGlassContainerEffect()` with `spacing` |
| `.buttonStyle(.glass)` | Insert `UIVisualEffectView` as button subview |

## WidgetKit Implementation

### Rendering Modes

Widgets support two rendering modes that affect how Liquid Glass is displayed:

| Mode | Description |
|------|-------------|
| **Full Color** | Default mode. Displays all colors, images, and transparency as designed. |
| **Accented** | Used when tinted or clear appearance is chosen. Primary and accented content tinted white (iOS and macOS). Background replaced with themed glass or tinted color effect. |

### Accented Mode

Detect the rendering mode and adapt layout accordingly. Use `.widgetAccentable()` to mark views that should be tinted in accented mode:

```swift
struct MyWidgetView: View {
    @Environment(\.widgetRenderingMode) var renderingMode

    var body: some View {
        if renderingMode == .accented {
            // Layout optimized for accented mode
            AccentedWidgetLayout()
        } else {
            // Standard full-color layout
            FullColorWidgetLayout()
        }
    }
}
```

#### Grouping Accent Content

```swift
HStack(alignment: .center, spacing: 0) {
    VStack(alignment: .leading) {
        Text("Widget Title")
            .font(.headline)
            .widgetAccentable()
        Text("Widget Subtitle")
    }
    Image(systemName: "star.fill")
        .widgetAccentable()
}
```

#### Image Rendering in Accented Mode

```swift
Image("myImage")
    .widgetAccentedRenderingMode(.monochrome)
```

### Container Backgrounds

Define a container background for your widget content:

```swift
var body: some View {
    VStack {
        // Widget content
    }
    .containerBackground(for: .widget) {
        Color.blue.opacity(0.2)
    }
}
```

### Background Removal

Prevent the system from removing the widget background. Note that marking a background as non-removable excludes the widget from contexts that require removable backgrounds (iPad Lock Screen, StandBy):

```swift
var body: some WidgetConfiguration {
    StaticConfiguration(kind: "MyWidget", provider: Provider()) { entry in
        MyWidgetView(entry: entry)
    }
    .containerBackgroundRemovable(false)
}
```

### visionOS Textures and Mounting Styles

#### Widget Textures

```swift
// Default glass texture
.widgetTexture(.glass)

// Paper-like texture
.widgetTexture(.paper)
```

#### Mounting Styles

```swift
.supportedMountingStyles([.recessed, .elevated])
```

| Style | Description |
|-------|-------------|
| `.recessed` | Widget appears embedded into a vertical surface |
| `.elevated` | Widget appears on top of a surface |

### Custom Glass Elements in Widgets

Apply `.glassEffect()` and `.buttonStyle(.glass)` directly within widget views:

```swift
// Glass text element
Text("Custom Element")
    .padding()
    .glassEffect()

// Glass image element
Image(systemName: "star.fill")
    .frame(width: 60, height: 60)
    .glassEffect(.regular, in: .rect(cornerRadius: 12))

// Glass button in widget
Button("Action") { }
    .buttonStyle(.glass)
```

## Best Practices

1. **Use GlassEffectContainer** for multiple glass views
   - Improves rendering performance
   - Enables morphing transitions

2. **Apply glass effect last** in modifier chain
   - After frame, padding, and content modifiers

3. **Choose appropriate spacing** in containers
   - Controls when effects blend together

4. **Use animations** for state changes
   - Enables smooth morphing transitions

5. **Add interactivity** for touchable elements
   - `.interactive()` for buttons and controls

6. **Tint sparingly** — reserve tint for the primary action
   - See Design Rules: tinting everything makes nothing stand out

7. **Consistent shapes** across your app
   - Establish a shape language (all capsules, or all rounded rects)

## Checklist

### SwiftUI
- [ ] Use `.glassEffect()` instead of `.background(.material)`
- [ ] Wrap multiple glass views in `GlassEffectContainer`
- [ ] Add `@Namespace` for morphing transitions
- [ ] Use `.glassEffectID()` on views that appear/disappear
- [ ] Add `.interactive()` for touchable elements
- [ ] Use `.buttonStyle(.glass)` for glass buttons
- [ ] Test animations for smooth morphing

### UIKit
- [ ] Use `UIVisualEffectView` with `UIGlassEffect` for glass surfaces
- [ ] Set `isInteractive = true` on glass effects for touchable elements
- [ ] Wrap multiple glass views in `UIGlassContainerEffect`
- [ ] Configure scroll view edge effects (`.automatic` or `.hard`)
- [ ] Use `UIScrollEdgeElementContainerInteraction` for scroll-coordinated toolbars
- [ ] Use `hidesSharedBackground` for toolbar items that need independent glass

### WidgetKit
- [ ] Detect `widgetRenderingMode` and adapt layout for accented mode
- [ ] Mark accent content with `.widgetAccentable()`
- [ ] Set `.widgetAccentedRenderingMode()` on images
- [ ] Define `.containerBackground(for: .widget)` for backgrounds
- [ ] Use `.containerBackgroundRemovable(false)` only when necessary
- [ ] Apply `.glassEffect()` and `.buttonStyle(.glass)` in widget views
- [ ] Configure `.widgetTexture()` and `.supportedMountingStyles()` for visionOS

### General
- [ ] Glass only on the navigation layer — never on content (tables, lists)
- [ ] No glass stacked on glass; one variant (Regular or Clear) per interface
- [ ] Only the primary action is tinted
- [ ] Consider performance with many glass effects
- [ ] Support both light and dark appearances

## References

### SwiftUI
- [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views)
- [Landmarks: Building an app with Liquid Glass](https://developer.apple.com/documentation/SwiftUI/Landmarks-Building-an-app-with-Liquid-Glass)
- [SwiftUI GlassEffectContainer](https://developer.apple.com/documentation/SwiftUI/GlassEffectContainer)

### AppKit
- [AppKit NSGlassEffectView](https://developer.apple.com/documentation/AppKit/NSGlassEffectView)

### UIKit
- [UIKit UIGlassEffect](https://developer.apple.com/documentation/UIKit/UIGlassEffect)
- [UIKit UIGlassContainerEffect](https://developer.apple.com/documentation/UIKit/UIGlassContainerEffect)
- [UIKit UIVisualEffectView](https://developer.apple.com/documentation/UIKit/UIVisualEffectView)
- [UIScrollEdgeElementContainerInteraction](https://developer.apple.com/documentation/UIKit/UIScrollEdgeElementContainerInteraction)

### WidgetKit
- [WidgetKit Rendering Modes](https://developer.apple.com/documentation/WidgetKit/WidgetRenderingMode)
- [widgetAccentable()](https://developer.apple.com/documentation/SwiftUI/View/widgetAccentable(_:))
- [containerBackground(for:)](https://developer.apple.com/documentation/SwiftUI/View/containerBackground(for:alignment:content:))

