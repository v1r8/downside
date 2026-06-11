import SwiftUI
import AppKit
import ServiceManagement
import Sparkle

struct SettingsView: View {
    @AppStorage(PrefKey.folderPath) private var folderPath = ""
    @AppStorage(PrefKey.corner) private var corner = HotCorner.bottomRight.rawValue
    @AppStorage(PrefKey.dwell) private var dwell = 0.12
    @AppStorage(PrefKey.hotCornerEnabled) private var hotCornerEnabled = true

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Pasta") {
                LabeledContent("Pasta monitorada") {
                    HStack(spacing: 8) {
                        Text(displayPath)
                            .truncationMode(.middle)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                        Button("Alterar…") { pickFolder() }
                    }
                }
            }

            Section("Canto ativo") {
                Toggle("Abrir painel pelo canto da tela", isOn: $hotCornerEnabled)

                Picker("Canto", selection: $corner) {
                    ForEach(HotCorner.allCases) { corner in
                        Text(corner.label).tag(corner.rawValue)
                    }
                }
                .disabled(!hotCornerEnabled)

                VStack(alignment: .leading) {
                    Slider(value: $dwell, in: 0.05...0.5) {
                        Text("Atraso de ativação")
                    }
                    .disabled(!hotCornerEnabled)
                    Text("\(Int(dwell * 1000)) ms no canto antes de abrir")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Geral") {
                Toggle("Abrir ao iniciar a sessão", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        setLaunchAtLogin(enabled)
                    }
            }

            Section("Atualizações") {
                AutomaticUpdatesToggle(updater: AppState.shared.updater.updater)
                Button("Verificar atualizações agora") {
                    AppState.shared.updater.checkForUpdates()
                }
                LabeledContent("Versão", value: versionString)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private var displayPath: String {
        let path = Prefs.folderURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home)
            ? path.replacingOccurrences(of: home, with: "~")
            : path
    }

    private var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = Prefs.folderURL
        panel.prompt = "Escolher"

        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            folderPath = url.path
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

private struct AutomaticUpdatesToggle: View {
    let updater: SPUUpdater

    @State private var automatic: Bool

    init(updater: SPUUpdater) {
        self.updater = updater
        _automatic = State(initialValue: updater.automaticallyChecksForUpdates)
    }

    var body: some View {
        Toggle("Buscar atualizações automaticamente", isOn: $automatic)
            .onChange(of: automatic) { _, enabled in
                updater.automaticallyChecksForUpdates = enabled
            }
    }
}
