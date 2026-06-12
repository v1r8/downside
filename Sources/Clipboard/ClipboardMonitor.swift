import AppKit
import Combine

/// Observa o clipboard (quando habilitado nas configurações) e
/// transforma capturas em itens da linha do tempo: arquivos entram por
/// referência; texto e imagens são salvos no cofre do app.
@MainActor
final class ClipboardMonitor: ObservableObject {
    @Published private(set) var items: [FileItem] = []

    private var timer: Timer?
    private var lastChange = NSPasteboard.general.changeCount

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard Prefs.clipboardTimelineEnabled else { return }
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChange else { return }
        lastChange = pasteboard.changeCount

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
           !urls.isEmpty, urls.allSatisfy(\.isFileURL) {
            add(urls.map { FileItem(url: $0) })
            return
        }

        if let image = NSImage(pasteboard: pasteboard),
           let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            let url = destination(name: "Clipboard \(stamp())", ext: "png")
            if (try? png.write(to: url)) != nil {
                add([FileItem(url: url)])
            }
            return
        }

        if let text = pasteboard.string(forType: .string),
           text.trimmingCharacters(in: .whitespacesAndNewlines).count > 2 {
            let url = destination(name: "Clipboard \(stamp())", ext: "txt")
            if (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil {
                add([FileItem(url: url)])
            }
        }
    }

    private func add(_ newItems: [FileItem]) {
        var merged = newItems + items.filter { existing in
            !newItems.contains(where: { $0.url == existing.url })
        }
        if merged.count > 50 {
            merged = Array(merged.prefix(50))
        }
        items = merged
    }

    private func stamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter.string(from: Date())
    }

    private func destination(name: String, ext: String) -> URL {
        Prefs.supportDirectory("Clipboard").appendingPathComponent("\(name).\(ext)")
    }
}
