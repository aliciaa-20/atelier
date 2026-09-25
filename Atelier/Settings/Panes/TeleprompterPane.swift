import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Script editor + file drop + reading options. Edits save automatically
/// (debounced) to `ScriptStore`; the model reloads on the store's change
/// notification and restarts from the top.
struct TeleprompterPane: View {
    @AppStorage(AtelierSettings.teleprompterEnabledKey) private var enabled = true
    @AppStorage(AtelierSettings.teleprompterWPMKey) private var wpm = TeleprompterScroll.defaultWPM
    @AppStorage(AtelierSettings.teleprompterMonoFontKey) private var mono = false
    @AppStorage(AtelierSettings.teleprompterFontSizeKey) private var fontSize = 15.0
    @AppStorage(AtelierSettings.teleprompterPauseOnHoverKey) private var pauseOnHover = true
    @AppStorage(AtelierSettings.ghostModeKey) private var ghostMode = false
    @AppStorage(AtelierSettings.teleprompterHotkeysKey) private var hotkeys = false

    @AppStorage(AtelierSettings.teleprompterControlOrderKey) private var controlOrder = ""

    @State private var text = ""
    @State private var loaded = false
    @State private var saveTask: Task<Void, Never>?
    @State private var message: String?
    @State private var pendingImport: URL?
    @State private var dropTargeted = false

    var body: some View {
        Form {
            Section("Script") {
                Text("Add your script: paste or type it below, or drop a file onto the box under it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $text)
                        .font(.body)
                        .frame(minHeight: 150)
                        .accessibilityLabel("Script")
                        // A text view would otherwise take a dropped file for
                        // its own (inserting its path); route it to the importer.
                        .dropDestination(for: URL.self, action: handleDrop, isTargeted: { dropTargeted = $0 })
                    if text.isEmpty {
                        Text("Paste or type your script here")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 0)
                            .padding(.leading, 4)
                            .allowsHitTesting(false)
                    }
                }
                dropZone
                if let message {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                }
            }
            .disabled(!enabled)

            Section("Reading") {
                LabeledContent("Speed") {
                    Stepper(value: $wpm, in: TeleprompterScroll.wpmRange, step: 10) {
                        Text("\(Int(wpm)) WPM")
                    }
                }
                Picker("Font", selection: $mono) {
                    Text("Sans").tag(false)
                    Text("Mono").tag(true)
                }
                LabeledContent("Text size") {
                    Stepper(value: $fontSize, in: 12...22, step: 1) {
                        Text("\(Int(fontSize)) pt")
                    }
                }
                Toggle("Pause while the pointer is over the notch", isOn: $pauseOnHover)
            }
            .disabled(!enabled)

            Section("Top bar") {
                Text("Choose where each control sits around the camera. Drag a row, or use its arrows: rows above the camera cutout appear on its left, rows below it on its right.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                topBarPreview
                // A real `List` (its own table view), like the Tabs pane: drags
                // on plain rows inside a `Form` don't work.
                List {
                    ForEach(order, id: \.self) { name in controlRow(name) }
                        .onMove { source, destination in
                            var items = order
                            items.move(fromOffsets: source, toOffset: destination)
                            controlOrder = TeleprompterControlLayout.normalized(items).joined(separator: ",")
                        }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .frame(height: CGFloat(order.count) * 40)
                Button("Reset Order") { controlOrder = "" }
                    .disabled(controlOrder.isEmpty)
            }
            .disabled(!enabled)

            Section("Privacy and shortcuts") {
                Toggle("Ghost Mode", isOn: $ghostMode)
                Text("Hides the whole notch from screen sharing and recordings. It is still visible to you.")
                    .font(.callout).foregroundStyle(.secondary)
                Toggle("Global shortcuts", isOn: $hotkeys)
                Text("⌃⌥P play or pause, ⌃⌥↑ faster, ⌃⌥↓ slower. Work while another app is in front.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            guard !loaded else { return }
            text = ScriptStore.shared.load()
            loaded = true
        }
        .onChange(of: text) { scheduleSave() }
        .onChange(of: wpm) { _, value in TeleprompterModel.shared.setWPM(value) }
        .dropDestination(for: URL.self, action: handleDrop, isTargeted: { dropTargeted = $0 })
        .confirmationDialog("Replace the current script?", isPresented: .init(
            get: { pendingImport != nil },
            set: { if !$0 { pendingImport = nil } }
        ), presenting: pendingImport) { url in
            Button("Replace") { importFile(url) }
            Button("Cancel", role: .cancel) {}
        } message: { url in
            Text("\(url.lastPathComponent) will replace what's in the editor.")
        }
    }

    private var order: [String] {
        TeleprompterControlLayout.normalized(controlOrder.split(separator: ",").map(String.init))
    }

    private func title(for name: String) -> String {
        switch name {
        case "play": "Play and pause"
        case "speed": "Speed"
        case "ring": "Time remaining"
        default: "Camera cutout"
        }
    }

    private func symbol(for name: String) -> String {
        switch name {
        case "play": "playpause.fill"
        case "speed": "gauge.with.dots.needle.33percent"
        case "ring": "timer"
        default: "camera"
        }
    }

    /// A live mock-up of the notch's top bar: your controls on either side of
    /// the camera cutout, so the result of a reorder is obvious.
    private var topBarPreview: some View {
        let layout = TeleprompterControlLayout.resolve(stored: controlOrder.split(separator: ",").map(String.init))
        return HStack(spacing: 10) {
            HStack(spacing: 10) {
                ForEach(layout.left, id: \.self) { previewIcon($0) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.14))
                .frame(width: 56, height: 16)
                .overlay(Text("camera").font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary))
            HStack(spacing: 10) {
                ForEach(layout.right, id: \.self) { previewIcon($0) }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.85)))
        .animation(.easeOut(duration: 0.2), value: controlOrder)
        .accessibilityHidden(true)
    }

    private func previewIcon(_ control: TeleprompterControl) -> some View {
        Image(systemName: symbol(for: control.rawValue))
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
    }

    /// One row. The camera row is a marker, not a control: it stands for the
    /// physical camera cutout in the middle of the notch.
    private func controlRow(_ name: String) -> some View {
        let isNotch = name == TeleprompterControlLayout.notchToken
        let index = order.firstIndex(of: name) ?? 0
        return HStack(spacing: 10) {
            Image(systemName: symbol(for: name))
                .frame(width: 22)
                .foregroundStyle(isNotch ? Color.secondary : Color.primary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title(for: name))
                    .foregroundStyle(isNotch ? Color.secondary : Color.primary)
                if isNotch {
                    Text("the notch itself, not a control")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Button { shift(name, by: -1) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.borderless)
                .disabled(index == 0)
                .help("Move up")
            Button { shift(name, by: 1) } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.borderless)
                .disabled(index == order.count - 1)
                .help("Move down")
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Move up") { shift(name, by: -1) }
        .accessibilityAction(named: "Move down") { shift(name, by: 1) }
    }

    private func shift(_ name: String, by delta: Int) {
        guard let index = order.firstIndex(of: name), order.indices.contains(index + delta) else { return }
        controlOrder = TeleprompterControlLayout.move(name, onto: order[index + delta], in: order).joined(separator: ",")
    }

    /// The advertised drop target: dashed box that lights up while a file is
    /// dragged over it.
    private var dropZone: some View {
        VStack(spacing: 6) {
            Image(systemName: dropTargeted ? "arrow.down.doc.fill" : "arrow.down.doc")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(dropTargeted ? Color.accentColor : .secondary)
            Text("Drop a file here")
                .font(.headline)
            Text(".txt   .md   .doc   .docx   .rtf")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Choose File") { chooseFile() }
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(dropTargeted ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    dropTargeted ? Color.accentColor : Color.secondary.opacity(0.5),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )
        )
        .contentShape(Rectangle())
        .dropDestination(for: URL.self, action: handleDrop, isTargeted: { dropTargeted = $0 })
        .scaleEffect(dropTargeted ? 1.015 : 1)
        .animation(.spring(duration: 0.3, bounce: 0.25), value: dropTargeted)
        .accessibilityElement(children: .contain)
    }

    /// Only real files: a dragged web link would otherwise be read over the
    /// network on the main thread.
    private func handleDrop(_ urls: [URL], _ location: CGPoint) -> Bool {
        guard let url = urls.first, url.isFileURL else { return false }
        requestImport(url)
        return true
    }

    /// Debounced so typing doesn't rewrite the file and reset playback on
    /// every keystroke.
    private func scheduleSave() {
        guard loaded else { return }
        saveTask?.cancel()
        let current = text
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            // Opening the pane sets `text` from the store; saving it back
            // unchanged would still reload the model.
            guard current != ScriptStore.shared.load() else { return }
            do { try ScriptStore.shared.save(current) }
            catch { message = "Couldn't save the script" }
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ScriptImporter.supportedExtensions
            .compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        requestImport(url)
    }

    /// Never overwrites typed text without asking (Alicia's global rule).
    private func requestImport(_ url: URL) {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            importFile(url)
        } else {
            pendingImport = url
        }
    }

    private func importFile(_ url: URL) {
        do {
            text = try ScriptImporter.importText(from: url)
            message = "Imported \(url.lastPathComponent)"
        } catch let error as ScriptImporter.ImportError {
            message = error.message          // current script left untouched
        } catch {
            message = "Couldn't read that file"
        }
    }
}
