import AppKit
import ApplicationServices

/// Descobre o documento aberto na janela em foco do app frontal,
/// via Acessibilidade (o macOS pede a permissão uma única vez).
enum ActiveDocument {
    @MainActor
    static func grab() -> URL? {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { return nil }
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            axApp, kAXFocusedWindowAttribute as CFString, &window
        ) == .success, let window else { return nil }

        var document: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            window as! AXUIElement, kAXDocumentAttribute as CFString, &document
        ) == .success, let path = document as? String else { return nil }

        if path.hasPrefix("file://"), let url = URL(string: path) {
            return url
        }
        return URL(fileURLWithPath: path)
    }
}
