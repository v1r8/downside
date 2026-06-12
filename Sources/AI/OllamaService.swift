import Foundation

/// Cliente do Ollama (http://127.0.0.1:11434): LLM local baixável para
/// nomear pilhas com profundidade, grátis e privado. O usuário instala
/// o Ollama uma vez; o modelo pode ser baixado pelas Configurações.
enum OllamaService {
    private static let base = URL(string: "http://127.0.0.1:11434")!

    enum ServiceError: Error {
        case notRunning
        case badResponse
    }

    /// Ollama instalado e rodando?
    static func isRunning() async -> Bool {
        var request = URLRequest(url: base.appendingPathComponent("api/tags"))
        request.timeoutInterval = 2
        guard let (_, response) = try? await URLSession.shared.data(for: request) else {
            return false
        }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    /// O modelo configurado já foi baixado?
    static func hasModel(_ name: String) async -> Bool {
        var request = URLRequest(url: base.appendingPathComponent("api/tags"))
        request.timeoutInterval = 2
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]]
        else { return false }
        let target = name.split(separator: ":").first.map(String.init) ?? name
        return models.contains { model in
            guard let modelName = model["name"] as? String else { return false }
            return modelName == name || modelName.hasPrefix("\(target):")
        }
    }

    static func generate(prompt: String, model: String = Prefs.ollamaModel) async throws -> String {
        var request = URLRequest(url: base.appendingPathComponent("api/generate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.timeoutInterval = 60
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "prompt": prompt,
            "stream": false,
            "options": ["temperature": 0.3, "num_predict": 60],
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["response"] as? String
        else { throw ServiceError.badResponse }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Baixa o modelo via /api/pull (stream), reportando o status.
    static func pull(
        model: String = Prefs.ollamaModel,
        progress: @escaping @Sendable (String) -> Void
    ) async throws {
        var request = URLRequest(url: base.appendingPathComponent("api/pull"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.timeoutInterval = 3600
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "name": model,
            "stream": true,
        ])
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ServiceError.badResponse
        }
        for try await line in bytes.lines {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = json["status"] as? String
            else { continue }
            if let total = json["total"] as? Double,
               let completed = json["completed"] as? Double, total > 0 {
                progress("\(status) — \(Int(completed / total * 100))%")
            } else {
                progress(status)
            }
        }
    }

    /// Resposta curta de uma linha (títulos/nomes) — nil se o Ollama
    /// não estiver rodando ou o modelo não estiver baixado.
    static func completeShort(prompt: String) async -> String? {
        let model = Prefs.ollamaModel
        guard await isRunning(), await hasModel(model) else { return nil }
        guard let raw = try? await generate(prompt: prompt, model: model) else {
            return nil
        }
        let title = raw
            .components(separatedBy: .newlines).first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'.")) ?? ""
        return title.isEmpty ? nil : String(title.prefix(60))
    }
}
