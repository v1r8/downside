import SwiftUI
import AppKit
import ServiceManagement
import Sparkle

struct SettingsView: View {
    @AppStorage(PrefKey.folderPath) private var folderPath = ""
    @AppStorage(PrefKey.corners) private var cornersRaw = HotCorner.bottomRight.rawValue
    @AppStorage(PrefKey.dwell) private var dwell = 0.12
    @AppStorage(PrefKey.hotCornerEnabled) private var hotCornerEnabled = true
    @AppStorage(PrefKey.hideMargin) private var hideMargin = 220.0
    @AppStorage(PrefKey.autoHideEnabled) private var autoHideEnabled = true
    @AppStorage(PrefKey.viewMode) private var viewModeRaw = ViewMode.grid.rawValue
    @AppStorage(PrefKey.uiScale) private var uiScale = 1.0
    @AppStorage(PrefKey.hoverPreviewEnabled) private var hoverPreviewEnabled = true
    @AppStorage(PrefKey.hoverPreviewDelay) private var hoverPreviewDelay = 0.8
    @AppStorage(PrefKey.hoverPreviewSize) private var hoverPreviewSize = 1.0

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

            Section("Cantos ativos") {
                Toggle("Abrir painel pelos cantos da tela", isOn: $hotCornerEnabled)

                ForEach(HotCorner.allCases) { corner in
                    Toggle(corner.label, isOn: cornerBinding(corner))
                        .disabled(!hotCornerEnabled)
                }

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

            Section("Exibição") {
                Picker("Modo de exibição", selection: $viewModeRaw) {
                    ForEach(ViewMode.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                Text(currentModeDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Fechar ao afastar o mouse", isOn: $autoHideEnabled)

                VStack(alignment: .leading) {
                    Slider(value: $hideMargin, in: 50...600) {
                        Text("Área antes de fechar")
                    }
                    .disabled(!autoHideEnabled)
                    Text(autoHideEnabled
                        ? "O painel fecha quando o mouse se afasta ~\(Int(hideMargin)) px dele"
                        : "O painel só fecha por clique fora, Esc ou canto ativo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading) {
                    Slider(value: $uiScale, in: 0.8...1.8) {
                        Text("Tamanho da interface")
                    }
                    Text("Interface em \(Int(uiScale * 100))% — fontes, ícones, previews e painel")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Preview ao parar o mouse") {
                Toggle("Mostrar preview do item sob o mouse", isOn: $hoverPreviewEnabled)

                VStack(alignment: .leading) {
                    Slider(value: $hoverPreviewDelay, in: 0.2...2.5) {
                        Text("Tempo até aparecer")
                    }
                    .disabled(!hoverPreviewEnabled)
                    Text(String(format: "%.1f s parado sobre o item antes do preview abrir", hoverPreviewDelay))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading) {
                    Slider(value: $hoverPreviewSize, in: 0.7...1.8) {
                        Text("Tamanho do preview")
                    }
                    .disabled(!hoverPreviewEnabled)
                    Text("Cartão de preview em \(Int(hoverPreviewSize * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                DisclosureGroup("Tamanho por categoria") {
                    ForEach(PreviewCategory.allCases) { category in
                        PreviewCategorySizeRow(category: category)
                            .disabled(!hoverPreviewEnabled)
                    }
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

    private var currentModeDescription: String {
        (ViewMode(rawValue: viewModeRaw) ?? .grid).description
    }

    private func cornerBinding(_ corner: HotCorner) -> Binding<Bool> {
        Binding(
            get: {
                cornersRaw.split(separator: ",").contains(Substring(corner.rawValue))
            },
            set: { enabled in
                var corners = Set(cornersRaw.split(separator: ",").map(String.init))
                if enabled {
                    corners.insert(corner.rawValue)
                } else {
                    corners.remove(corner.rawValue)
                }
                cornersRaw = corners.sorted().joined(separator: ",")
            }
        )
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

/// Slider de tamanho do preview para uma categoria de arquivo,
/// multiplicado sobre o tamanho geral.
private struct PreviewCategorySizeRow: View {
    let category: PreviewCategory
    @AppStorage private var size: Double

    init(category: PreviewCategory) {
        self.category = category
        _size = AppStorage(wrappedValue: 1.0, category.prefKey)
    }

    var body: some View {
        HStack {
            Text(category.label)
                .frame(width: 130, alignment: .leading)
            Slider(value: $size, in: 0.7...1.8)
            Text("\(Int(size * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
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
