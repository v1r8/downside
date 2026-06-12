import AppKit

/// Favicons para os itens de link (.webloc): tenta o ícone do próprio
/// site (apple-touch-icon, favicon.ico) e cai num serviço de favicons
/// como último recurso. Cache em memória + disco (cofre do app).
@MainActor
enum FaviconLoader {
    private static var memory: [String: NSImage] = [:]
    private static var failed: Set<String> = []

    static func load(for link: URL) async -> NSImage? {
        guard let host = link.host?.lowercased() else { return nil }
        if let cached = memory[host] { return cached }
        guard !failed.contains(host) else { return nil }

        let file = Prefs.supportDirectory("Favicons")
            .appendingPathComponent("\(host).png")
        if let image = NSImage(contentsOf: file), image.isValid {
            memory[host] = image
            return image
        }

        let candidates = [
            "https://\(host)/apple-touch-icon.png",
            "https://\(host)/favicon.ico",
            "https://www.google.com/s2/favicons?sz=64&domain=\(host)",
        ]
        for raw in candidates {
            guard let url = URL(string: raw) else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 5
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  data.count > 100,
                  let image = NSImage(data: data),
                  image.isValid, image.size.width >= 16
            else { continue }
            if let tiff = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: file)
            }
            memory[host] = image
            return image
        }
        failed.insert(host)
        return nil
    }
}
