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
                TextEditor(text: $text)
                    .font(.body)
                    .frame(minHeight: 170)
                    .accessibilityLabel("Script")
                HStack {
                    Button("Choose File") { chooseFile() }
                    Text("or drop a .txt, .md, .doc, .docx or .rtf file anywhere here")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
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
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            requestImport(url)
            return true
        } isTargeted: { dropTargeted = $0 }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor, lineWidth: 2).padding(4)
                    .allowsHitTesting(false)
            }
        }
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
