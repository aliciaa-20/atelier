import AppKit
import SwiftUI

/// The System Monitor's Energy segment: a funny one-line verdict, then the
/// top energy-using apps as icon + name + relative bar. Deliberately no
/// numbers -- the bar length *is* the information (spec 2026-09-29).
/// Sampling is tied to this view being on screen (`onAppear`/`onDisappear`).
struct EnergyListView: View {
    @ObservedObject var source: EnergySource
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: NotchLayout.energyRowSpacing) {
            if !source.hasSample {
                message("Watching who's thirsty…", symbol: "eyes")
            } else if source.rows.isEmpty {
                message(EnergyMath.verdict(.napping, appName: ""), symbol: "moon.zzz")
            } else {
                let top = source.rows[0]
                Text(EnergyMath.verdict(EnergyMath.Tier(topWatts: top.watts), appName: top.name))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                ForEach(source.rows) { row in
                    EnergyRow(row: row, fraction: EnergyMath.fraction(watts: row.watts, topWatts: top.watts))
                }
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : NotchAnimations.standard, value: source.rows)
        .onAppear { source.start() }
        .onDisappear { source.stop() }
    }

    /// Shared empty-state style: soft card, one SF Symbol, one short line.
    private func message(_ text: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: NotchLayout.cardCornerRadius))
        .accessibilityElement(children: .combine)
    }
}

private struct EnergyRow: View {
    let row: EnergyMath.AppEnergy
    let fraction: Double

    private var isAtelier: Bool { row.id == Bundle.main.bundleIdentifier }

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: AppIconCache.icon(forBundleID: row.id))
                .resizable()
                .frame(width: NotchLayout.energyIconSize, height: NotchLayout.energyIconSize)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(row.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if isAtelier {
                    Text("that's me, hi")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: NotchLayout.energyNameWidth, alignment: .leading)
            GeometryReader { geo in
                Capsule().fill(.white.opacity(0.10))
                    .overlay(alignment: .leading) {
                        Capsule().fill(.tint)
                            .frame(width: max(geo.size.width * fraction, NotchLayout.energyBarHeight))
                    }
            }
            .frame(height: NotchLayout.energyBarHeight)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        switch fraction {
        case 1...: "\(row.name), highest energy use"
        case 0.66...: "\(row.name), nearly as much"
        case 0.33...: "\(row.name), about half as much"
        default: "\(row.name), a little"
        }
    }
}

/// Tiny cache so we don't hit `NSWorkspace` for the same 5 icons every
/// 3-second refresh.
@MainActor
private enum AppIconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(forBundleID id: String) -> NSImage {
        if let cached = cache[id] { return cached }
        let image: NSImage
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            image = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            image = NSImage(systemSymbolName: "gearshape.2", accessibilityDescription: nil) ?? NSImage()
        }
        cache[id] = image
        return image
    }
}
