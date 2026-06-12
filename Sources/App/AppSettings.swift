import AppKit

enum HotCorner: String, CaseIterable, Identifiable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var id: String { rawValue }

    var label: String {
        switch self {
        case .topLeft: return "Superior esquerdo"
        case .topRight: return "Superior direito"
        case .bottomLeft: return "Inferior esquerdo"
        case .bottomRight: return "Inferior direito"
        }
    }

    /// Ponto exato do canto, em coordenadas globais.
    func point(in screenFrame: NSRect) -> NSPoint {
        switch self {
        case .bottomLeft: return NSPoint(x: screenFrame.minX, y: screenFrame.minY)
        case .bottomRight: return NSPoint(x: screenFrame.maxX, y: screenFrame.minY)
        case .topLeft: return NSPoint(x: screenFrame.minX, y: screenFrame.maxY)
        case .topRight: return NSPoint(x: screenFrame.maxX, y: screenFrame.maxY)
        }
    }

    /// Zona quente do canto, em coordenadas globais da tela.
    func zone(in screenFrame: NSRect, size: CGFloat) -> NSRect {
        switch self {
        case .bottomLeft:
            return NSRect(x: screenFrame.minX, y: screenFrame.minY, width: size, height: size)
        case .bottomRight:
            return NSRect(x: screenFrame.maxX - size, y: screenFrame.minY, width: size, height: size)
        case .topLeft:
            return NSRect(x: screenFrame.minX, y: screenFrame.maxY - size, width: size, height: size)
        case .topRight:
            return NSRect(x: screenFrame.maxX - size, y: screenFrame.maxY - size, width: size, height: size)
        }
    }
}

enum ViewMode: String, CaseIterable, Identifiable {
    case grid
    case list
    case minimal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .grid: return "Grade"
        case .list: return "Lista"
        case .minimal: return "Minimalista"
        }
    }

    var icon: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .list: return "list.bullet"
        case .minimal: return "text.alignleft"
        }
    }

    var description: String {
        switch self {
        case .grid: return "Miniaturas grandes em grade, como o Finder"
        case .list: return "Linhas compactas com preview, tamanho e data"
        case .minimal: return "Só os nomes, sem fundo, com leve escurecimento da tela"
        }
    }
}

/// Laterais da tela que também podem abrir o painel.
enum ScreenEdge: String, CaseIterable, Identifiable {
    case left
    case right

    var id: String { rawValue }

    var label: String {
        switch self {
        case .left: return "Lateral esquerda"
        case .right: return "Lateral direita"
        }
    }
}

/// Categorias de conteúdo do preview, para ajuste de tamanho individual.
enum PreviewCategory: String, CaseIterable, Identifiable {
    case image, pdf, text, table, folder, audio

    var id: String { rawValue }

    var label: String {
        switch self {
        case .image: return "Imagens e outros"
        case .pdf: return "PDFs"
        case .text: return "Texto"
        case .table: return "Tabelas (CSV)"
        case .folder: return "Pastas"
        case .audio: return "Áudio"
        }
    }

    var prefKey: String { "previewSize.\(rawValue)" }
}

enum PrefKey {
    static let folderPath = "folderPath"
    /// Antiga preferência de canto único (mantida para migração).
    static let corner = "hotCorner"
    /// Cantos ativos, separados por vírgula.
    static let corners = "hotCorners"
    /// Laterais ativas, separadas por vírgula.
    static let edges = "hotEdges"
    static let dwell = "hotCornerDwell"
    static let dragOpenRadius = "dragOpenRadius"
    static let hotCornerEnabled = "hotCornerEnabled"
    static let hideMargin = "hideMargin"
    static let autoHideEnabled = "autoHideOnLeave"
    static let viewMode = "viewMode"
    static let uiScale = "uiScale"
    static let hoverPreviewEnabled = "hoverPreviewEnabled"
    static let hoverPreviewDelay = "hoverPreviewDelay"
    static let hoverPreviewSize = "hoverPreviewSize"
    static let stackPreviewEnabled = "stackPreviewEnabled"
    static let stackPreviewDelay = "stackPreviewDelay"
    static let stackReplaceDelay = "stackReplaceDelay"
    static let clipboardTimeline = "clipboardTimeline"
    static let clipboardStyle = "clipboardStyle"
    static let claudeAPIKey = "claudeAPIKey"
    static let showDragHandle = "showDragHandle"
    static let accentColorHex = "accentColorHex"
    static let accentIntensity = "accentIntensity"
    static let outputColorHex = "outputColorHex"
    static let outputIntensity = "outputIntensity"
    static let archiveHoverPreview = "archiveHoverPreview"
    static let cleanButtonEnabled = "cleanButtonEnabled"
    static let clipboardMarkIntensity = "clipboardMarkIntensity"
    static let clipboardBarWidth = "clipboardBarWidth"
    static let stackTitleDetail = "stackTitleDetail"
    static let bulkBadgeStyle = "bulkBadgeStyle"
    static let historyLayout = "historyLayout"
    static let ollamaModel = "ollamaModel"
    static let panelWidth = "panelWidth"
    static let panelHeight = "panelHeight"
}

/// Acesso às preferências fora do SwiftUI (as views usam @AppStorage
/// com as mesmas chaves).
enum Prefs {
    static var folderURL: URL {
        if let path = UserDefaults.standard.string(forKey: PrefKey.folderPath), !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    static var corners: Set<HotCorner> {
        if let raw = UserDefaults.standard.string(forKey: PrefKey.corners) {
            // String vazia = usuário desligou todos os cantos de propósito.
            return Set(raw.split(separator: ",").compactMap { HotCorner(rawValue: String($0)) })
        }
        // Migra a preferência antiga de canto único.
        if let old = UserDefaults.standard.string(forKey: PrefKey.corner),
           let corner = HotCorner(rawValue: old) {
            return [corner]
        }
        return [.bottomRight]
    }

    static var edges: Set<ScreenEdge> {
        guard let raw = UserDefaults.standard.string(forKey: PrefKey.edges) else { return [] }
        return Set(raw.split(separator: ",").compactMap { ScreenEdge(rawValue: String($0)) })
    }

    /// Raio ao redor do canto/lateral que abre o painel durante arrastos.
    static var dragOpenRadius: CGFloat {
        let value = UserDefaults.standard.double(forKey: PrefKey.dragOpenRadius)
        guard value >= 50, value <= 400 else { return 130 }
        return CGFloat(value)
    }

    static var dwell: TimeInterval {
        let value = UserDefaults.standard.double(forKey: PrefKey.dwell)
        return value > 0 ? value : 0.12
    }

    static var hotCornerEnabled: Bool {
        UserDefaults.standard.object(forKey: PrefKey.hotCornerEnabled) as? Bool ?? true
    }

    /// Distância (px) que o mouse pode se afastar do painel antes de
    /// ele fechar sozinho.
    static var hideMargin: CGFloat {
        let value = UserDefaults.standard.double(forKey: PrefKey.hideMargin)
        return value > 0 ? CGFloat(value) : 220
    }

    /// Se desligado, o painel só fecha por clique fora, Esc, canto
    /// ativo de novo ou ação explícita.
    static var autoHideEnabled: Bool {
        UserDefaults.standard.object(forKey: PrefKey.autoHideEnabled) as? Bool ?? true
    }

    static var viewMode: ViewMode {
        ViewMode(rawValue: UserDefaults.standard.string(forKey: PrefKey.viewMode) ?? "") ?? .grid
    }

    /// Fator de escala da interface (fontes, ícones, previews, painel).
    static var uiScale: CGFloat {
        let value = UserDefaults.standard.double(forKey: PrefKey.uiScale)
        guard value >= 0.8, value <= 2.0 else { return 1.0 }
        return CGFloat(value)
    }

    static var hoverPreviewEnabled: Bool {
        UserDefaults.standard.object(forKey: PrefKey.hoverPreviewEnabled) as? Bool ?? true
    }

    /// Tempo parado sobre um item antes do preview aparecer.
    static var hoverPreviewDelay: TimeInterval {
        let value = UserDefaults.standard.double(forKey: PrefKey.hoverPreviewDelay)
        return value > 0 ? value : 0.8
    }

    /// Fator de tamanho do cartão de preview (multiplicado pela escala
    /// geral da interface).
    static var hoverPreviewSize: CGFloat {
        let value = UserDefaults.standard.double(forKey: PrefKey.hoverPreviewSize)
        guard value >= 0.7, value <= 1.8 else { return 1.0 }
        return CGFloat(value)
    }

    /// Tempo segurando um arrasto sobre uma pilha para substituir o
    /// conteúdo dela.
    static var stackReplaceDelay: TimeInterval {
        let value = UserDefaults.standard.double(forKey: PrefKey.stackReplaceDelay)
        guard value >= 1, value <= 6 else { return 3.0 }
        return value
    }

    /// Preview global (todos os docs da pilha) ao pairar no chip.
    static var stackPreviewEnabled: Bool {
        UserDefaults.standard.object(forKey: PrefKey.stackPreviewEnabled) as? Bool ?? true
    }

    static var stackPreviewDelay: TimeInterval {
        let value = UserDefaults.standard.double(forKey: PrefKey.stackPreviewDelay)
        guard value >= 0.3, value <= 3 else { return 1.0 }
        return value
    }

    /// Inclui capturas do clipboard na linha do tempo da pasta.
    static var clipboardTimelineEnabled: Bool {
        UserDefaults.standard.object(forKey: PrefKey.clipboardTimeline) as? Bool ?? false
    }

    /// Estilo visual dos itens vindos do clipboard (1 a 5).
    static var clipboardStyle: Int {
        let value = UserDefaults.standard.integer(forKey: PrefKey.clipboardStyle)
        return (1...5).contains(value) ? value : 2
    }

    /// Alça de reposicionamento visível no header.
    static var showDragHandle: Bool {
        UserDefaults.standard.object(forKey: PrefKey.showDragHandle) as? Bool ?? true
    }

    /// Preview global ao pairar sobre fichas arquivadas.
    static var archiveHoverPreview: Bool {
        UserDefaults.standard.object(forKey: PrefKey.archiveHoverPreview) as? Bool ?? true
    }

    /// Botão flutuante de limpeza (deck de cartas).
    static var cleanButtonEnabled: Bool {
        UserDefaults.standard.object(forKey: PrefKey.cleanButtonEnabled) as? Bool ?? true
    }

    /// Visibilidade da marcação de itens do clipboard.
    static var clipboardMarkIntensity: Double {
        let value = UserDefaults.standard.double(forKey: PrefKey.clipboardMarkIntensity)
        return (0.3...1.6).contains(value) ? value : 1.0
    }

    /// Largura da barra lateral (estilo 3) do clipboard.
    static var clipboardBarWidth: CGFloat {
        let value = UserDefaults.standard.double(forKey: PrefKey.clipboardBarWidth)
        return (2...6).contains(value) ? CGFloat(value) : 2.5
    }

    /// Detalhamento do título de pilhas: 1 = só nomes; 2 = nomes +
    /// trechos do conteúdo.
    static var stackTitleDetail: Int {
        let value = UserDefaults.standard.integer(forKey: PrefKey.stackTitleDetail)
        return (1...2).contains(value) ? value : 2
    }

    /// Indicador de ações em massa: 1 = carta no fim do deck;
    /// 2 = estrela à esquerda; 3 = ponto no contador/título; 4 = nenhum.
    static var bulkBadgeStyle: Int {
        let value = UserDefaults.standard.integer(forKey: PrefKey.bulkBadgeStyle)
        return (1...4).contains(value) ? value : 1
    }

    /// Organização do fichário (HistoryLayout).
    static var historyLayout: Int {
        let value = UserDefaults.standard.integer(forKey: PrefKey.historyLayout)
        return (1...6).contains(value) ? value : 1
    }

    /// Modelo do Ollama para nomeação local.
    static var ollamaModel: String {
        let value = UserDefaults.standard.string(forKey: PrefKey.ollamaModel)?
            .trimmingCharacters(in: .whitespaces)
        return (value?.isEmpty == false) ? value! : "llama3.2:3b"
    }

    /// Chave da API do Claude para os recursos de IA (opcional).
    static var claudeAPIKey: String? {
        let key = UserDefaults.standard.string(forKey: PrefKey.claudeAPIKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (key?.isEmpty == false) ? key : nil
    }

    /// Cofre do app em Application Support.
    static func supportDirectory(_ subfolder: String) -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("Downside/\(subfolder)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Ajuste fino de tamanho do preview por categoria de arquivo,
    /// multiplicado sobre o tamanho geral.
    static func previewCategorySize(_ category: PreviewCategory) -> CGFloat {
        let value = UserDefaults.standard.double(forKey: category.prefKey)
        guard value >= 0.7, value <= 1.8 else { return 1.0 }
        return CGFloat(value)
    }

    static var panelSize: NSSize {
        let w = UserDefaults.standard.double(forKey: PrefKey.panelWidth)
        let h = UserDefaults.standard.double(forKey: PrefKey.panelHeight)
        return NSSize(width: w > 200 ? w : 560, height: h > 160 ? h : 420)
    }

    /// Posição do painel na grade 3×3 da tela (snap proporcional),
    /// escolhida pelo usuário ao arrastar pela alça.
    static var panelAnchor: (col: Int, row: Int)? {
        guard UserDefaults.standard.object(forKey: "panelAnchor.col") != nil else { return nil }
        return (
            UserDefaults.standard.integer(forKey: "panelAnchor.col"),
            UserDefaults.standard.integer(forKey: "panelAnchor.row")
        )
    }

    static func setPanelAnchor(col: Int, row: Int) {
        UserDefaults.standard.set(col, forKey: "panelAnchor.col")
        UserDefaults.standard.set(row, forKey: "panelAnchor.row")
    }

    static func clearPanelAnchor() {
        UserDefaults.standard.removeObject(forKey: "panelAnchor.col")
        UserDefaults.standard.removeObject(forKey: "panelAnchor.row")
    }

    /// Tamanho que o usuário deu ao painel arrastando pelas bordas,
    /// memorizado por modo de exibição.
    static func savedPanelSize(for mode: ViewMode) -> NSSize? {
        let w = UserDefaults.standard.double(forKey: "panelSize.\(mode.rawValue).w")
        let h = UserDefaults.standard.double(forKey: "panelSize.\(mode.rawValue).h")
        guard w >= 300, h >= 240 else { return nil }
        return NSSize(width: w, height: h)
    }

    static func savePanelSize(_ size: NSSize, for mode: ViewMode) {
        UserDefaults.standard.set(Double(size.width), forKey: "panelSize.\(mode.rawValue).w")
        UserDefaults.standard.set(Double(size.height), forKey: "panelSize.\(mode.rawValue).h")
    }
}
