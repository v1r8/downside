import Foundation
import Combine

/// Nomeação inteligente de documentos e itens do clipboard: a LLM
/// LOCAL (Apple Intelligence ou Ollama — sem custo, sem internet) lê
/// o conteúdo e propõe um apelido legível. Os nomes são SÓ visuais —
/// nada é renomeado no disco — e ficam guardados no cofre do app.
enum SmartNamer {
    /// Algum backend local disponível? (Claude não entra aqui — seria
    /// custo por arquivo.)
    static func backendAvailable() async -> Bool {
        if LocalNamer.isAvailable { return true }
        guard await OllamaService.isRunning() else { return false }
        return await OllamaService.hasModel(Prefs.ollamaModel)
    }

    static func name(for url: URL) async -> String? {
        var context = "Arquivo: \(url.lastPathComponent)"
        if let line = await TitlePrompt.excerpt(for: url, deep: true) {
            context += "\nConteúdo: \(line)"
        }
        let isLink = url.pathExtension.lowercased() == "webloc"
        let linkHint = isLink
            ? """
             Este item é um LINK: identifique o conteúdo da página/vídeo \
            pelo título, canal/autor e descrição fornecidos (ex.: \
            "Outliers — entrevista com gestor da Genoa", "Artigo do \
            Valor sobre juros"). Nunca descreva como "link" ou "site".
            """
            : ""
        let prompt = """
        Sugira um nome ESPECÍFICO e claro (3 a 8 palavras, em português, \
        sem extensão, sem aspas, sem barras) que identifique este \
        documento pelo conteúdo real, como uma pessoa o descreveria numa \
        frase curta. CITE nomes próprios presentes no conteúdo — empresa, \
        programa, pessoas, projeto, produto. NUNCA use genéricos como \
        "relatório financeiro" ou "link da internet".\(linkHint) Responda \
        APENAS com o nome:

        \(context)
        """
        var raw = await LocalNamer.complete(prompt: prompt)
        if raw == nil {
            raw = await OllamaService.completeShort(prompt: prompt)
        }
        guard let raw else { return nil }
        let name = raw
            .components(separatedBy: .newlines).first!
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'.“”"))
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: ":", with: " ")
        guard name.count > 2 else { return nil }
        return String(name.prefix(64))
    }
}

/// Guarda os apelidos gerados (path → nome) e processa a fila de
/// nomeação um doc por vez — o item em nomeação mostra o efeito
/// mágico no lugar do título, sem bloquear cliques nem arrastos.
@MainActor
final class SmartNameStore: ObservableObject {
    static let shared = SmartNameStore()

    @Published private(set) var names: [String: String] = [:]
    @Published private(set) var pending: Set<String> = []

    private var attempted: Set<String> = []
    private var queue: [URL] = []
    private var working = false
    private var backendOK: Bool?
    private var backendCheckedAt = Date.distantPast

    private var storeURL: URL {
        Prefs.supportDirectory("SmartNames").appendingPathComponent("nomes.json")
    }

    private init() { load() }

    // MARK: - Consulta (usada pelas células)

    func isPending(_ item: FileItem) -> Bool {
        pending.contains(item.url.path)
    }

    func hasName(_ url: URL) -> Bool { names[url.path] != nil }

    /// Título exibido: apelido da IA, ou o nome original sem a
    /// extensão (que vira a etiqueta de tipo ao lado).
    func title(for item: FileItem) -> String {
        guard Prefs.smartNamesEnabled else { return item.name }
        if let custom = names[item.url.path] { return custom }
        let ext = item.url.pathExtension
        if !ext.isEmpty,
           item.name.lowercased().hasSuffix(".\(ext.lowercased())"),
           item.name.count > ext.count + 1 {
            return String(item.name.dropLast(ext.count + 1))
        }
        return item.name
    }

    /// Etiqueta de tipo — a pílula à direita do título.
    func tag(for item: FileItem) -> String? {
        guard Prefs.smartNamesEnabled, !item.isDirectory else { return nil }
        let ext = item.url.pathExtension.lowercased()
        guard !ext.isEmpty else { return nil }
        if ext == "webloc" { return "LINK" }
        if ext == "jpeg" { return "JPG" }
        return String(ext.prefix(6)).uppercased()
    }

    // MARK: - Nomeação

    /// Pede um nome para o item se ele ainda não tem (chamado quando a
    /// célula aparece — só os itens visíveis entram na fila).
    func ensureName(_ item: FileItem) {
        guard Prefs.smartNamesEnabled, !item.isDirectory else { return }
        let path = item.url.path
        guard names[path] == nil,
              !attempted.contains(path),
              !pending.contains(path)
        else { return }
        attempted.insert(path)
        queue.append(item.url)
        kick()
    }

    /// Força uma (re)nomeação — menu de contexto.
    func requestName(_ item: FileItem, force: Bool = false) {
        guard !item.isDirectory else { return }
        if force {
            attempted.remove(item.url.path)
            names.removeValue(forKey: item.url.path)
            backendOK = nil
        }
        ensureName(item)
    }

    /// Volta ao nome original (e não renomeia de novo sozinho).
    func clearName(_ url: URL) {
        names.removeValue(forKey: url.path)
        attempted.insert(url.path)
        save()
    }

    func resetAll() {
        names.removeAll()
        attempted.removeAll()
        save()
    }

    private func kick() {
        guard !working, !queue.isEmpty else { return }
        working = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.backendOK != true
                || Date().timeIntervalSince(self.backendCheckedAt) > 120 {
                self.backendOK = await SmartNamer.backendAvailable()
                self.backendCheckedAt = Date()
            }
            guard self.backendOK == true else {
                self.queue.removeAll()
                self.working = false
                return
            }
            while !self.queue.isEmpty {
                let url = self.queue.removeFirst()
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                self.pending.insert(url.path)
                let name = await SmartNamer.name(for: url)
                self.pending.remove(url.path)
                if let name { self.names[url.path] = name }
            }
            self.save()
            self.working = false
            self.kick()
        }
    }

    // MARK: - Persistência

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let stored = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }
        names = stored
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(names) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}
