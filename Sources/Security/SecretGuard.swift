import Foundation

/// Heurística 100% local para reconhecer textos copiados que parecem
/// senhas, chaves de API ou tokens — a linha do tempo do clipboard
/// pula esse conteúdo quando a proteção está ligada.
enum SecretSniffer {
    private static let knownPrefixes = [
        "sk-", "sk_", "pk_", "rk_",          // chaves de API (Anthropic, OpenAI, Stripe…)
        "ghp_", "gho_", "ghs_", "github_pat_", // GitHub
        "xoxb-", "xoxp-", "xoxs-",            // Slack
        "akia", "asia",                        // AWS access keys
        "aiza",                                // Google API keys
        "ya29.",                               // Google OAuth
        "eyj",                                 // JWTs
        "glpat-", "npm_", "pypi-",
    ]

    static func looksLikeSecret(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("PRIVATE KEY-----") { return true }

        // Só tokens únicos (sem espaços) levantam suspeita; frases e
        // textos comuns nunca são bloqueados.
        guard !trimmed.contains(where: \.isWhitespace), trimmed.count >= 12 else { return false }

        let lower = trimmed.lowercased()
        if knownPrefixes.contains(where: { lower.hasPrefix($0) }) { return true }

        // Caminhos de arquivo e endereços não contam.
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") || lower.hasPrefix("file://") {
            return false
        }

        // Sequência longa misturando maiúsculas, minúsculas e números
        // (com ou sem símbolos) tem cara de senha gerada.
        guard trimmed.count >= 20 else { return false }
        let hasUpper = trimmed.contains(where: \.isUppercase)
        let hasLower = trimmed.contains(where: \.isLowercase)
        let hasDigit = trimmed.contains(where: \.isNumber)
        return hasUpper && hasLower && hasDigit
    }
}

/// Sanitiza nomes de arquivo sugeridos por servidores em downloads:
/// fica só o último componente do caminho e nomes vazios/ocultos
/// caem num nome neutro com data.
enum SafeFileName {
    static func sanitize(_ suggested: String?, fallback: String) -> String {
        var name = (suggested ?? "").replacingOccurrences(of: "\\", with: "/")
        name = (name as NSString).lastPathComponent
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name.hasPrefix(".") {
            return fallback
        }
        return name
    }
}
