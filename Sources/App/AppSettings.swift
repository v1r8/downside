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

enum PrefKey {
    static let folderPath = "folderPath"
    /// Antiga preferência de canto único (mantida para migração).
    static let corner = "hotCorner"
    /// Cantos ativos, separados por vírgula.
    static let corners = "hotCorners"
    static let dwell = "hotCornerDwell"
    static let hotCornerEnabled = "hotCornerEnabled"
    static let hideMargin = "hideMargin"
    static let viewMode = "viewMode"
    static let uiScale = "uiScale"
    static let hoverPreviewEnabled = "hoverPreviewEnabled"
    static let hoverPreviewDelay = "hoverPreviewDelay"
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

    static var panelSize: NSSize {
        let w = UserDefaults.standard.double(forKey: PrefKey.panelWidth)
        let h = UserDefaults.standard.double(forKey: PrefKey.panelHeight)
        return NSSize(width: w > 200 ? w : 560, height: h > 160 ? h : 420)
    }
}
