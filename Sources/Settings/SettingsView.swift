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
            SecuritySettingsTab()
                .tabItem { Label("Segurança", systemImage: "lock.shield") }
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
    @AppStorage(PrefKey.cleanButtonEnabled) private var cleanButtonEnabled = true
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

            Toggle("Botão de limpeza (deck de cartas)", isOn: $cleanButtonEnabled)

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
    @AppStorage(PrefKey.outputColorHex) private var outputHex = ""
    @AppStorage(PrefKey.outputIntensity) private var outputIntensity = 1.0
    @AppStorage(PrefKey.clipboardStyle) private var clipboardStyle = 2
    @AppStorage(PrefKey.clipboardMarkIntensity) private var clipMarkIntensity = 1.0
    @AppStorage(PrefKey.clipboardBarWidth) private var clipBarWidth = 2.5
    @ObservedObject private var themeStore = ThemeStore.shared

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
                // Amostra ao vivo do resultado.
                LabeledContent("Prévia") {
                    HStack(spacing: 6) {
                        Capsule().fill(Theme.tint(0.25)).frame(width: 34, height: 14)
                        Capsule().fill(Theme.tint(0.6)).frame(width: 34, height: 14)
                        Text("12")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(GlassCapsule(tint: 0.7))
                    }
                }
            }

            Section("Outputs de ações em massa") {
                ColorPicker(
                    "Cor dos outputs (✨ e chips)",
                    selection: Binding(
                        get: { Color(hex: outputHex) ?? (Color(hex: accentHex) ?? .accentColor) },
                        set: { outputHex = $0.hexString ?? "" }
                    ),
                    supportsOpacity: false
                )
                Button("Usar a cor dos destaques") { outputHex = "" }
                VStack(alignment: .leading) {
                    Slider(value: $outputIntensity, in: 0.35...1.5) {
                        Text("Intensidade")
                    }
                    Text("Intensidade dos outputs: \(Int(outputIntensity * 100))%")
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
                VStack(alignment: .leading) {
                    Slider(value: $clipMarkIntensity, in: 0.3...1.6) {
                        Text("Visibilidade da marca")
                    }
                    Text("Marca do clipboard em \(Int(clipMarkIntensity * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if clipboardStyle == 3 {
                    VStack(alignment: .leading) {
                        Slider(value: $clipBarWidth, in: 2...6) {
                            Text("Largura da barra lateral")
                        }
                        Text("\(String(format: "%.1f", clipBarWidth)) px")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
    @AppStorage(PrefKey.historyLayout) private var historyLayout = 1
    @AppStorage(PrefKey.bulkBadgeStyle) private var bulkBadgeStyle = 1
    @AppStorage(PrefKey.holoCardFront) private var holoCardFront = false
    @ObservedObject private var config = BulkActionConfigStore.shared

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

            Section("Fichário e indicadores") {
                Picker("Organização do fichário", selection: $historyLayout) {
                    Text("Lista").tag(1)
                    Text("Grade").tag(2)
                    Text("Compacta").tag(3)
                    Text("Linha do tempo").tag(4)
                    Text("Mosaico").tag(5)
                    Text("Estantes por mês").tag(6)
                }
                Picker("Indicador de ações em massa", selection: $bulkBadgeStyle) {
                    Text("Carta holográfica no deck").tag(1)
                    Text("Estrela à esquerda").tag(2)
                    Text("Ponto no contador/título").tag(3)
                    Text("Nenhum").tag(4)
                }
                if bulkBadgeStyle == 1 {
                    Picker("Posição da carta", selection: $holoCardFront) {
                        Text("Atrás do deck").tag(false)
                        Text("À frente do deck").tag(true)
                    }
                }
            }

            Section("Ações em massa") {
                ForEach(config.items) { item in
                    BulkActionConfigRow(item: item)
                }
                Button("Restaurar padrão") {
                    config.reset()
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Linha editável de uma ação em massa: ícone, texto, ordem e ativação.
private struct BulkActionConfigRow: View {
    @ObservedObject private var config = BulkActionConfigStore.shared
    let item: BulkActionItem

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(BulkActionConfigStore.iconChoices, id: \.self) { icon in
                    Button {
                        update { $0.icon = icon }
                    } label: {
                        Label(icon, systemImage: icon)
                    }
                }
            } label: {
                Image(systemName: item.icon)
                    .frame(width: 20)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            TextField("Nome", text: Binding(
                get: { item.title },
                set: { value in update { $0.title = value } }
            ))
            .textFieldStyle(.roundedBorder)

            Button { config.move(item.id, up: true) } label: {
                Image(systemName: "chevron.up")
            }
            Button { config.move(item.id, up: false) } label: {
                Image(systemName: "chevron.down")
            }

            Toggle("", isOn: Binding(
                get: { item.enabled },
                set: { value in update { $0.enabled = value } }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .buttonStyle(.borderless)
    }

    private func update(_ change: (inout BulkActionItem) -> Void) {
        guard let index = config.items.firstIndex(where: { $0.id == item.id }) else { return }
        var copy = config.items[index]
        change(&copy)
        config.items[index] = copy
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
    @State private var apiKey = Prefs.claudeAPIKey ?? ""
    @AppStorage(PrefKey.stackTitleDetail) private var titleDetail = 1
    @AppStorage(PrefKey.ollamaModel) private var ollamaModel = "llama3.2:3b"
    @AppStorage(PrefKey.smartNames) private var smartNames = true

    @State private var ollamaStatus = "Verificando…"
    @State private var pullStatus: String?

    var body: some View {
        Form {
            Section("Nomeação de pilhas") {
                Picker("Detalhamento do título", selection: $titleDetail) {
                    Text("Só os nomes dos arquivos").tag(1)
                    Text("Nomes + trechos do conteúdo").tag(2)
                }
                LabeledContent("Apple Intelligence") {
                    Text(LocalNamer.isAvailable
                        ? "Disponível ✓ (no aparelho, grátis)"
                        : "Indisponível (requer macOS 26 com Apple Intelligence)")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Nomes inteligentes") {
                Toggle("Nomear documentos e clipboard com IA local", isOn: $smartNames)
                Text("""
                A LLM local (Apple Intelligence ou Ollama) lê o conteúdo e \
                dá um apelido legível aos docs — só na interface do \
                Downside; os arquivos no disco NÃO mudam. O tipo (PDF, \
                PNG, LINK…) vira uma etiqueta ao lado do título. Clique \
                com o botão direito num doc para forçar ou desfazer um nome.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
                Button("Esquecer nomes gerados") {
                    SmartNameStore.shared.resetAll()
                }
            }

            Section("Modelo local baixável (Ollama)") {
                LabeledContent("Status", value: ollamaStatus)
                TextField("Modelo", text: $ollamaModel, prompt: Text("llama3.2:3b"))

                HStack {
                    Button("Instalar Ollama…") {
                        NSWorkspace.shared.open(URL(string: "https://ollama.com/download")!)
                    }
                    Button(pullStatus == nil ? "Baixar modelo (~2 GB)" : "Baixando…") {
                        startPull()
                    }
                    .disabled(pullStatus != nil)
                    Button("Verificar") {
                        Task { await refreshStatus() }
                    }
                }

                if let pullStatus {
                    Text(pullStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("""
                Nomeação profunda, rápida e 100% local: instale o Ollama \
                (app gratuito), baixe o modelo uma vez e os títulos das \
                pilhas passam a ser gerados no seu Mac, sem internet e sem \
                custo. Ordem de uso: Apple Intelligence → Ollama → Claude → data.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .task { await refreshStatus() }

            SecureField("Chave da API do Claude", text: $apiKey, prompt: Text("sk-ant-…"))
                .onChange(of: apiKey) { _, value in
                    APIKeyVault.set(value)
                }
            Text("""
            Opcional. Habilita os recursos de IA: títulos automáticos no \
            fichário e as ações em massa "Resumir" e "Palavras-chave" nas \
            pilhas. Crie uma chave em console.anthropic.com — o uso é \
            cobrado pela Anthropic na sua conta. A chave fica guardada \
            no Keychain do macOS, cifrada pelo sistema.
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

    private func refreshStatus() async {
        guard await OllamaService.isRunning() else {
            ollamaStatus = "Ollama não está rodando"
            return
        }
        if await OllamaService.hasModel(ollamaModel) {
            ollamaStatus = "Pronto ✓ — \(ollamaModel) baixado"
        } else {
            ollamaStatus = "Rodando — modelo \(ollamaModel) ainda não baixado"
        }
    }

    private func startPull() {
        pullStatus = "Iniciando…"
        let model = ollamaModel
        Task {
            do {
                try await OllamaService.pull(model: model) { status in
                    Task { @MainActor in pullStatus = status }
                }
                pullStatus = nil
                await refreshStatus()
            } catch {
                pullStatus = "Falhou — o Ollama está rodando?"
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                pullStatus = nil
            }
        }
    }
}

// MARK: - Segurança

private struct SecuritySettingsTab: View {
    @AppStorage(PrefKey.clipboardSkipConcealed) private var skipConcealed = true
    @AppStorage(PrefKey.clipboardSkipTransient) private var skipTransient = true
    @AppStorage(PrefKey.clipboardSkipSecretLike) private var skipSecretLike = true
    @AppStorage(PrefKey.clipboardRetentionHours) private var retentionHours = 168.0
    @State private var clearedFlash = false

    var body: some View {
        Form {
            Section("Clipboard") {
                Toggle("Ignorar cópias de gerenciadores de senhas", isOn: $skipConcealed)
                Text("""
                1Password, Bitwarden e afins marcam o que copiam como \
                confidencial — com isso ligado, o Downside nunca guarda \
                esse conteúdo.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)

                Toggle("Ignorar conteúdo transitório/automático", isOn: $skipTransient)
                Text("Cópias marcadas pelos apps como descartáveis ou geradas automaticamente não entram na linha do tempo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Não guardar textos que parecem senhas ou chaves", isOn: $skipSecretLike)
                Text("""
                Detecção 100% local: tokens conhecidos (sk-…, ghp_…, JWT…) \
                e sequências longas sem espaços misturando maiúsculas, \
                minúsculas e números são pulados. Frases e textos comuns \
                nunca são afetados.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Histórico do clipboard") {
                Picker("Apagar automaticamente", selection: $retentionHours) {
                    Text("Depois de 1 hora").tag(1.0)
                    Text("Depois de 24 horas").tag(24.0)
                    Text("Depois de 7 dias").tag(168.0)
                    Text("Depois de 30 dias").tag(720.0)
                    Text("Nunca").tag(0.0)
                }
                Text("Itens antigos saem da linha do tempo e as cópias guardadas pelo app são apagadas de vez. Seus arquivos originais nunca são tocados.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(clearedFlash ? "Histórico limpo ✓" : "Limpar histórico do clipboard agora") {
                    AppState.shared.clipboard.clearAll()
                    clearedFlash = true
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        clearedFlash = false
                    }
                }
                .disabled(clearedFlash)
            }

            Section("Chave da API") {
                LabeledContent("Armazenamento") {
                    Text(ClaudeService.hasKey
                        ? "No Keychain do macOS ✓ (cifrada pelo sistema)"
                        : "Nenhuma chave configurada")
                        .foregroundStyle(.secondary)
                }
                Text("A chave do Claude vive no Keychain — não fica em nenhum arquivo de preferências e nunca sai deste Mac (só é enviada à API da Anthropic quando você usa os recursos de IA).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Onde seus dados ficam") {
                Text("""
                Tudo que o Downside guarda — clipboard, pilhas, fichário e \
                preferências — fica em Biblioteca → Application Support → \
                Downside, neste Mac. Nada é publicado nem sincronizado. \
                Downloads de links usam nomes sanitizados e nunca \
                sobrescrevem arquivos existentes.
                """)
                .font(.caption)
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
