import SwiftUI
import AppKit
import ServiceManagement
import Sparkle

/// Configurações em abas — cabe na tela e é redimensionável.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("Geral", systemImage: "gearshape") }
            TriggerSettingsTab()
                .tabItem { Label("Abertura", systemImage: "cursorarrow.motionlines") }
            DisplaySettingsTab()
                .tabItem { Label("Exibição", systemImage: "square.grid.2x2") }
            StackSettingsTab()
                .tabItem { Label("Pilhas", systemImage: "square.stack.3d.up") }
            PreviewSettingsTab()
                .tabItem { Label("Preview", systemImage: "eye") }
            AISettingsTab()
                .tabItem { Label("IA", systemImage: "sparkles") }
            UpdateSettingsTab()
                .tabItem { Label("Atualizações", systemImage: "arrow.triangle.2.circlepath") }
        }
        .frame(minWidth: 480, idealWidth: 520, minHeight: 360, idealHeight: 420)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

// MARK: - Geral

private struct GeneralSettingsTab: View {
    @AppStorage(PrefKey.folderPath) private var folderPath = ""
    @AppStorage(PrefKey.clipboardTimeline) private var clipboardTimeline = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            LabeledContent("Pasta monitorada") {
                HStack(spacing: 8) {
                    Text(displayPath)
                        .truncationMode(.middle)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                    Button("Alterar…") { pickFolder() }
                }
            }

            Toggle("Abrir ao iniciar a sessão", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    setLaunchAtLogin(enabled)
                }

            Toggle("Incluir clipboard na linha do tempo", isOn: $clipboardTimeline)
            Text("Capturas de texto, imagens e arquivos copiados aparecem junto com os itens da pasta.")
                .font(.caption)
                .foregroundStyle(.secondary)

            LabeledContent("Posição do painel") {
                Button("Restaurar padrão (canto que abriu)") {
                    Prefs.clearPanelAnchor()
                }
            }
        }
        .formStyle(.grouped)
    }

    private var displayPath: String {
        let path = Prefs.folderURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home)
            ? path.replacingOccurrences(of: home, with: "~")
            : path
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

// MARK: - Abertura

private struct TriggerSettingsTab: View {
    @AppStorage(PrefKey.corners) private var cornersRaw = HotCorner.bottomRight.rawValue
    @AppStorage(PrefKey.edges) private var edgesRaw = ""
    @AppStorage(PrefKey.dwell) private var dwell = 0.12
    @AppStorage(PrefKey.dragOpenRadius) private var dragOpenRadius = 130.0
    @AppStorage(PrefKey.hotCornerEnabled) private var hotCornerEnabled = true

    var body: some View {
        Form {
            Toggle("Abrir pelos cantos/laterais da tela", isOn: $hotCornerEnabled)

            Section("Cantos") {
                ForEach(HotCorner.allCases) { corner in
                    Toggle(corner.label, isOn: setBinding($cornersRaw, corner.rawValue))
                        .disabled(!hotCornerEnabled)
                }
            }

            Section("Laterais") {
                ForEach(ScreenEdge.allCases) { edge in
                    Toggle(edge.label, isOn: setBinding($edgesRaw, edge.rawValue))
                        .disabled(!hotCornerEnabled)
                }
            }

            Section("Ajustes") {
                VStack(alignment: .leading) {
                    Slider(value: $dwell, in: 0.05...0.5) { Text("Atraso de ativação") }
                        .disabled(!hotCornerEnabled)
                    Text("\(Int(dwell * 1000)) ms parado antes de abrir")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading) {
                    Slider(value: $dragOpenRadius, in: 50...400) { Text("Raio ao arrastar") }
                        .disabled(!hotCornerEnabled)
                    Text("Arrastando algo, abre a ~\(Int(dragOpenRadius)) px do canto/lateral")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Binding para conjuntos guardados como string separada por vírgula.
private func setBinding(_ raw: Binding<String>, _ value: String) -> Binding<Bool> {
    Binding(
        get: { raw.wrappedValue.split(separator: ",").contains(Substring(value)) },
        set: { enabled in
            var set = Set(raw.wrappedValue.split(separator: ",").map(String.init))
            if enabled { set.insert(value) } else { set.remove(value) }
            raw.wrappedValue = set.sorted().joined(separator: ",")
        }
    )
}

// MARK: - Exibição

private struct DisplaySettingsTab: View {
    @AppStorage(PrefKey.viewMode) private var viewModeRaw = ViewMode.grid.rawValue
    @AppStorage(PrefKey.uiScale) private var uiScale = 1.0
    @AppStorage(PrefKey.hideMargin) private var hideMargin = 220.0
    @AppStorage(PrefKey.autoHideEnabled) private var autoHideEnabled = true
    @AppStorage(PrefKey.showDragHandle) private var showDragHandle = true
    @AppStorage(PrefKey.accentColorHex) private var accentHex = ""
    @AppStorage(PrefKey.accentIntensity) private var accentIntensity = 1.0
    @AppStorage(PrefKey.clipboardStyle) private var clipboardStyle = 2

    var body: some View {
        Form {
            Picker("Modo de exibição", selection: $viewModeRaw) {
                ForEach(ViewMode.allCases) { mode in
                    Text(mode.label).tag(mode.rawValue)
                }
            }
            Text((ViewMode(rawValue: viewModeRaw) ?? .grid).description)
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading) {
                Slider(value: $uiScale, in: 0.8...1.8) { Text("Tamanho da interface") }
                Text("Interface em \(Int(uiScale * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Destaques") {
                ColorPicker(
                    "Cor dos destaques",
                    selection: Binding(
                        get: { Color(hex: accentHex) ?? .accentColor },
                        set: { accentHex = $0.hexString ?? "" }
                    ),
                    supportsOpacity: false
                )
                Button("Usar cor do sistema") { accentHex = "" }
                VStack(alignment: .leading) {
                    Slider(value: $accentIntensity, in: 0.35...1.0) {
                        Text("Intensidade")
                    }
                    Text("Transparência dos destaques: \(Int(accentIntensity * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Interface") {
                Toggle("Mostrar alça de reposicionamento (≡)", isOn: $showDragHandle)
                Picker("Itens do clipboard", selection: $clipboardStyle) {
                    Text("Borda tracejada").tag(1)
                    Text("Selo de clipboard").tag(2)
                    Text("Barra lateral").tag(3)
                    Text("Degradê suave").tag(4)
                    Text("Etiqueta CLIP").tag(5)
                }
            }

            Section("Fechamento") {
                Toggle("Fechar ao afastar o mouse", isOn: $autoHideEnabled)
                VStack(alignment: .leading) {
                    Slider(value: $hideMargin, in: 50...600) { Text("Área antes de fechar") }
                        .disabled(!autoHideEnabled)
                    Text(autoHideEnabled
                        ? "Fecha quando o mouse se afasta ~\(Int(hideMargin)) px"
                        : "Só fecha por clique fora, Esc ou canto ativo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Pilhas

private struct StackSettingsTab: View {
    @AppStorage(PrefKey.stackReplaceDelay) private var stackReplaceDelay = 3.0
    @AppStorage(PrefKey.stackPreviewEnabled) private var stackPreviewEnabled = true
    @AppStorage(PrefKey.stackPreviewDelay) private var stackPreviewDelay = 1.0
    @AppStorage(PrefKey.archiveHoverPreview) private var archiveHoverPreview = true

    private var archiveHoverBinding: Binding<Bool> {
        $archiveHoverPreview
    }

    var body: some View {
        Form {
            VStack(alignment: .leading) {
                Slider(value: $stackReplaceDelay, in: 1...6) { Text("Segurar para substituir") }
                Text(String(format: "Segurar um arrasto sobre uma pilha por %.1f s substitui o conteúdo", stackReplaceDelay))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Preview global da pilha") {
                Toggle("Mostrar todos os docs ao pairar no chip", isOn: $stackPreviewEnabled)
                VStack(alignment: .leading) {
                    Slider(value: $stackPreviewDelay, in: 0.3...3) { Text("Tempo até aparecer") }
                        .disabled(!stackPreviewEnabled)
                    Text(String(format: "%.1f s parado sobre a pilha", stackPreviewDelay))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Também nas fichas do fichário", isOn: archiveHoverBinding)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Preview

private struct PreviewSettingsTab: View {
    @AppStorage(PrefKey.hoverPreviewEnabled) private var hoverPreviewEnabled = true
    @AppStorage(PrefKey.hoverPreviewDelay) private var hoverPreviewDelay = 0.8
    @AppStorage(PrefKey.hoverPreviewSize) private var hoverPreviewSize = 1.0

    var body: some View {
        Form {
            Toggle("Mostrar preview do item sob o mouse", isOn: $hoverPreviewEnabled)

            VStack(alignment: .leading) {
                Slider(value: $hoverPreviewDelay, in: 0.2...2.5) { Text("Tempo até aparecer") }
                    .disabled(!hoverPreviewEnabled)
                Text(String(format: "%.1f s parado sobre o item", hoverPreviewDelay))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading) {
                Slider(value: $hoverPreviewSize, in: 0.7...1.8) { Text("Tamanho do preview") }
                    .disabled(!hoverPreviewEnabled)
                Text("Cartão em \(Int(hoverPreviewSize * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Tamanho por categoria") {
                ForEach(PreviewCategory.allCases) { category in
                    PreviewCategorySizeRow(category: category)
                        .disabled(!hoverPreviewEnabled)
                }
            }
        }
        .formStyle(.grouped)
    }
}

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

// MARK: - IA

private struct AISettingsTab: View {
    @AppStorage(PrefKey.claudeAPIKey) private var apiKey = ""

    var body: some View {
        Form {
            SecureField("Chave da API do Claude", text: $apiKey, prompt: Text("sk-ant-…"))
            Text("""
            Opcional. Habilita os recursos de IA: títulos automáticos no \
            fichário e as ações em massa "Resumir" e "Palavras-chave" nas \
            pilhas. Crie uma chave em console.anthropic.com — o uso é \
            cobrado pela Anthropic na sua conta. A chave fica salva apenas \
            neste Mac.
            """)
            .font(.caption)
            .foregroundStyle(.secondary)

            LabeledContent("Status") {
                Text(ClaudeService.hasKey ? "Chave configurada ✓" : "Sem chave — recursos de IA desativados")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Atualizações

private struct UpdateSettingsTab: View {
    var body: some View {
        Form {
            AutomaticUpdatesToggle(updater: AppState.shared.updater.updater)
            Button("Verificar atualizações agora") {
                AppState.shared.updater.checkForUpdates()
            }
            LabeledContent("Versão", value: versionString)
        }
        .formStyle(.grouped)
    }

    private var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
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
