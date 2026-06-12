import Foundation

enum FileKind: CaseIterable {
    case pdf, image, video, audio, archive, spreadsheet, document, presentation, folder, installer

    var label: String {
        switch self {
        case .pdf: return "PDFs"
        case .image: return "Imagens"
        case .video: return "Vídeos"
        case .audio: return "Áudios"
        case .archive: return "Compactados"
        case .spreadsheet: return "Planilhas"
        case .document: return "Documentos"
        case .presentation: return "Apresentações"
        case .folder: return "Pastas"
        case .installer: return "Apps e instaladores"
        }
    }
}

struct ParsedQuery {
    var kinds: Set<FileKind> = []
    var dateRange: ClosedRange<Date>?
    var dateLabel: String?
    var minSize: Int64?
    var maxSize: Int64?
    var sizeLabel: String?
    var nameTerms: [String] = []

    var isEmpty: Bool {
        kinds.isEmpty && dateRange == nil && minSize == nil && maxSize == nil && nameTerms.isEmpty
    }

    /// Resumo legível de como a busca foi interpretada
    /// (ex.: "PDFs · hoje · “contrato”").
    var summary: String {
        var parts: [String] = []
        parts.append(contentsOf: kinds.map(\.label).sorted())
        if let dateLabel { parts.append(dateLabel) }
        if let sizeLabel { parts.append(sizeLabel) }
        parts.append(contentsOf: nameTerms.map { "“\($0)”" })
        return parts.joined(separator: " · ")
    }
}

/// Interpretador local de buscas em linguagem natural (pt-BR + termos
/// comuns em inglês). Entende tipo de arquivo, períodos e tamanhos:
///   "pdfs de hoje", "imagens grandes", "planilhas dessa semana",
///   "vídeos de junho", "zip maior que 50 mb", "contrato ontem".
enum NaturalSearch {
    // MARK: - Vocabulário

    private static let kindWords: [String: FileKind] = {
        var map: [String: FileKind] = [:]
        let groups: [(FileKind, [String])] = [
            (.pdf, ["pdf", "pdfs"]),
            (.image, ["imagem", "imagens", "foto", "fotos", "figura", "figuras",
                      "print", "prints", "screenshot", "screenshots", "captura", "capturas",
                      "png", "jpg", "jpeg", "gif", "heic"]),
            (.video, ["video", "videos", "filme", "filmes", "gravacao", "gravacoes",
                      "mp4", "mov"]),
            (.audio, ["audio", "audios", "musica", "musicas", "som", "sons", "mp3", "wav"]),
            (.archive, ["zip", "zips", "rar", "compactado", "compactados",
                        "comprimido", "comprimidos", "7z", "tar"]),
            (.spreadsheet, ["planilha", "planilhas", "excel", "xls", "xlsx", "csv",
                            "tabela", "tabelas"]),
            (.document, ["documento", "documentos", "doc", "docx", "word",
                         "texto", "textos", "txt", "nota", "notas"]),
            (.presentation, ["apresentacao", "apresentacoes", "ppt", "pptx",
                             "slide", "slides", "keynote"]),
            (.folder, ["pasta", "pastas", "diretorio", "diretorios", "folder"]),
            (.installer, ["app", "apps", "aplicativo", "aplicativos",
                          "instalador", "instaladores", "dmg", "pkg"]),
        ]
        for (kind, words) in groups {
            for word in words { map[word] = kind }
        }
        return map
    }()

    private static let extensionKinds: [String: FileKind] = {
        var map: [String: FileKind] = [:]
        let groups: [(FileKind, [String])] = [
            (.pdf, ["pdf"]),
            (.image, ["png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "bmp", "svg"]),
            (.video, ["mp4", "mov", "mkv", "avi", "webm", "m4v"]),
            (.audio, ["mp3", "wav", "aac", "m4a", "flac", "ogg"]),
            (.archive, ["zip", "rar", "7z", "tar", "gz", "bz2", "xz"]),
            (.spreadsheet, ["xls", "xlsx", "csv", "numbers", "ods"]),
            (.document, ["doc", "docx", "txt", "rtf", "pages", "md", "odt"]),
            (.presentation, ["ppt", "pptx", "key", "odp"]),
            (.installer, ["dmg", "pkg", "app"]),
        ]
        for (kind, exts) in groups {
            for ext in exts { map[ext] = kind }
        }
        return map
    }()

    private static let months: [String: Int] = [
        "janeiro": 1, "fevereiro": 2, "marco": 3, "abril": 4, "maio": 5, "junho": 6,
        "julho": 7, "agosto": 8, "setembro": 9, "outubro": 10, "novembro": 11, "dezembro": 12,
    ]

    private static let stopwords: Set<String> = [
        "de", "da", "do", "das", "dos", "a", "o", "as", "os", "um", "uma", "uns", "umas",
        "que", "com", "sem", "em", "no", "na", "nos", "nas", "e", "ou", "pra", "para",
        "me", "mostre", "mostra", "mostrar", "exibe", "exiba", "liste", "lista", "listar",
        "busca", "buscar", "busque", "procura", "procurar", "procure", "encontre",
        "achar", "ache", "quero", "ver", "todos", "todas", "todo", "toda",
        "arquivo", "arquivos", "item", "itens", "coisa", "coisas",
        "baixei", "baixados", "baixadas", "recebi", "recebidos", "salvei", "salvos",
        "aqui", "ai", "la", "meu", "meus", "minha", "minhas", "esse", "essa", "este", "esta",
        "desse", "dessa", "deste", "desta", "nesse", "nessa", "neste", "nesta",
    ]

    // MARK: - Parse

    static func parse(_ text: String) -> ParsedQuery {
        var query = ParsedQuery()
        let normalized = normalize(text)
        var tokens = normalized
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let day: TimeInterval = 86_400

        var index = 0
        var consumed = Set<Int>()

        func number(at i: Int) -> Double? {
            guard i < tokens.count else { return nil }
            return Double(tokens[i].replacingOccurrences(of: ",", with: "."))
        }

        func bytes(_ value: Double, unit: String) -> Int64? {
            switch unit {
            case "kb", "k": return Int64(value * 1_000)
            case "mb", "m", "mega", "megas": return Int64(value * 1_000_000)
            case "gb", "g", "giga", "gigas": return Int64(value * 1_000_000_000)
            default: return nil
            }
        }

        while index < tokens.count {
            let token = tokens[index]
            defer { index += 1 }
            if consumed.contains(index) { continue }

            // Tipos de arquivo
            if let kind = kindWords[token] {
                query.kinds.insert(kind)
                continue
            }

            // Datas
            switch token {
            case "hoje":
                query.dateRange = today...(today + day)
                query.dateLabel = "hoje"
                continue
            case "ontem":
                query.dateRange = (today - day)...today
                query.dateLabel = "ontem"
                continue
            case "anteontem":
                query.dateRange = (today - 2 * day)...(today - day)
                query.dateLabel = "anteontem"
                continue
            case "recente", "recentes", "novo", "novos", "nova", "novas":
                query.dateRange = (now - 2 * day)...(now + day)
                query.dateLabel = "últimas 48h"
                continue
            case "semana":
                if index + 1 < tokens.count, tokens[index + 1] == "passada" {
                    consumed.insert(index + 1)
                    if let interval = calendar.dateInterval(of: .weekOfYear, for: now - 7 * day) {
                        query.dateRange = interval.start...interval.end
                        query.dateLabel = "semana passada"
                    }
                } else if let interval = calendar.dateInterval(of: .weekOfYear, for: now) {
                    query.dateRange = interval.start...interval.end
                    query.dateLabel = "esta semana"
                }
                continue
            case "mes":
                if index + 1 < tokens.count, tokens[index + 1] == "passado" {
                    consumed.insert(index + 1)
                    if let lastMonth = calendar.date(byAdding: .month, value: -1, to: now),
                       let interval = calendar.dateInterval(of: .month, for: lastMonth) {
                        query.dateRange = interval.start...interval.end
                        query.dateLabel = "mês passado"
                    }
                } else if let interval = calendar.dateInterval(of: .month, for: now) {
                    query.dateRange = interval.start...interval.end
                    query.dateLabel = "este mês"
                }
                continue
            case "ultimos", "ultimas":
                if let value = number(at: index + 1), index + 2 < tokens.count {
                    let unit = tokens[index + 2]
                    var seconds: TimeInterval?
                    switch unit {
                    case "minuto", "minutos": seconds = value * 60
                    case "hora", "horas": seconds = value * 3_600
                    case "dia", "dias": seconds = value * day
                    case "semana", "semanas": seconds = value * 7 * day
                    case "mes", "meses": seconds = value * 30 * day
                    default: break
                    }
                    if let seconds {
                        consumed.insert(index + 1)
                        consumed.insert(index + 2)
                        query.dateRange = (now - seconds)...(now + day)
                        query.dateLabel = "últimos \(Int(value)) \(unit)"
                    }
                }
                continue
            default:
                break
            }

            if let month = months[token] {
                var components = calendar.dateComponents([.year], from: now)
                components.month = month
                components.day = 1
                if let start = calendar.date(from: components) {
                    let adjusted = start > now
                        ? calendar.date(byAdding: .year, value: -1, to: start) ?? start
                        : start
                    if let interval = calendar.dateInterval(of: .month, for: adjusted) {
                        query.dateRange = interval.start...interval.end
                        query.dateLabel = token
                    }
                }
                continue
            }

            // Tamanhos
            switch token {
            case "grande", "grandes", "pesado", "pesados", "gigante", "gigantes":
                query.minSize = 50_000_000
                query.sizeLabel = "> 50 MB"
                continue
            case "pequeno", "pequenos", "pequena", "pequenas", "leve", "leves":
                query.maxSize = 1_000_000
                query.sizeLabel = "< 1 MB"
                continue
            case "maior", "maiores", "acima", "mais":
                var i = index + 1
                if i < tokens.count, tokens[i] == "que" || tokens[i] == "de" {
                    consumed.insert(i)
                    i += 1
                }
                if let value = number(at: i), i + 1 < tokens.count,
                   let size = bytes(value, unit: tokens[i + 1]) {
                    consumed.insert(i)
                    consumed.insert(i + 1)
                    query.minSize = size
                    query.sizeLabel = "> \(tokens[i]) \(tokens[i + 1].uppercased())"
                }
                continue
            case "menor", "menores", "abaixo", "menos", "ate":
                var i = index + 1
                if i < tokens.count, tokens[i] == "que" || tokens[i] == "de" {
                    consumed.insert(i)
                    i += 1
                }
                if let value = number(at: i), i + 1 < tokens.count,
                   let size = bytes(value, unit: tokens[i + 1]) {
                    consumed.insert(i)
                    consumed.insert(i + 1)
                    query.maxSize = size
                    query.sizeLabel = "< \(tokens[i]) \(tokens[i + 1].uppercased())"
                }
                continue
            default:
                break
            }

            if stopwords.contains(token) { continue }
            if token.count >= 2 {
                query.nameTerms.append(token)
            }
        }

        return query
    }

    // MARK: - Match

    /// `content`: texto indexado do arquivo (já normalizado) — cada
    /// termo pode casar no NOME ou no CONTEÚDO.
    static func matches(_ item: FileItem, query: ParsedQuery, content: String? = nil) -> Bool {
        if !query.kinds.isEmpty {
            guard let kind = kind(of: item), query.kinds.contains(kind) else { return false }
        }
        if let range = query.dateRange, !range.contains(item.date) {
            return false
        }
        if let minSize = query.minSize, item.size < minSize {
            return false
        }
        if let maxSize = query.maxSize, item.isDirectory || item.size > maxSize {
            return false
        }
        if !query.nameTerms.isEmpty {
            let name = normalize(item.name)
            for term in query.nameTerms {
                if name.contains(term) { continue }
                if content?.contains(term) == true { continue }
                // Tolerância a typos: o termo pode estar escrito com
                // 1–2 erros de digitação no nome ou no conteúdo.
                if fuzzyContains(name, term: term) { continue }
                if let content, fuzzyContains(String(content.prefix(4_000)), term: term) {
                    continue
                }
                return false
            }
        }
        return true
    }

    // MARK: - Tolerância a typos

    /// O termo aparece (com até 1–2 erros, conforme o tamanho) em
    /// alguma palavra do texto?
    static func fuzzyContains(_ haystack: String, term: String) -> Bool {
        guard term.count >= 4 else { return false }
        let limit = term.count >= 8 ? 2 : 1
        let target = Array(term)
        for word in haystack.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            guard abs(word.count - term.count) <= limit else { continue }
            if editDistance(Array(word), target, limit: limit) <= limit {
                return true
            }
        }
        return false
    }

    /// Distância de edição com teto — sai cedo quando o melhor da
    /// linha já estoura o limite.
    private static func editDistance(_ a: [Character], _ b: [Character], limit: Int) -> Int {
        guard !a.isEmpty, !b.isEmpty else { return max(a.count, b.count) }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [Int](repeating: 0, count: b.count + 1)
            current[0] = i
            var rowMin = current[0]
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                rowMin = min(rowMin, current[j])
            }
            if rowMin > limit { return limit + 1 }
            previous = current
        }
        return previous[b.count]
    }

    static func kind(of item: FileItem) -> FileKind? {
        if item.isDirectory { return .folder }
        return extensionKinds[item.url.pathExtension.lowercased()]
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive],
                     locale: Locale(identifier: "pt_BR"))
    }
}
