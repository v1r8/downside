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

enum PrefKey {
    static let folderPath = "folderPath"
    static let corner = "hotCorner"
    static let dwell = "hotCornerDwell"
    static let hotCornerEnabled = "hotCornerEnabled"
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

    static var corner: HotCorner {
        HotCorner(rawValue: UserDefaults.standard.string(forKey: PrefKey.corner) ?? "") ?? .bottomRight
    }

    static var dwell: TimeInterval {
        let value = UserDefaults.standard.double(forKey: PrefKey.dwell)
        return value > 0 ? value : 0.12
    }

    static var hotCornerEnabled: Bool {
        UserDefaults.standard.object(forKey: PrefKey.hotCornerEnabled) as? Bool ?? true
    }

    static var panelSize: NSSize {
        let w = UserDefaults.standard.double(forKey: PrefKey.panelWidth)
        let h = UserDefaults.standard.double(forKey: PrefKey.panelHeight)
        return NSSize(width: w > 200 ? w : 560, height: h > 160 ? h : 420)
    }
}
