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
