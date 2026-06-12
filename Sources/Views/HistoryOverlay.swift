import SwiftUI
import AppKit

/// Fichário: histórico de pilhas arquivadas, com busca por título e
/// nomes de arquivos. Pilhas que passaram por ações em massa têm fundo
/// levemente destacado.
struct HistoryOverlay: View {
    @ObservedObject private var store = StackHistoryStore.shared
    @EnvironmentObject private var panel: PanelController
    let scale: CGFloat

    @State private var query = ""

    private var filtered: [ArchivedStack] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return store.archived }
        let needle = trimmed.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        return store.archived.filter { entry in
            let haystack = (entry.title + " " + entry.paths.joined(separator: " "))
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            return haystack.contains(needle)
        }
    }

    var body: some View {
        VStack(spacing: 8 * scale) {
            HStack(spacing: 4 * scale) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10 * scale))
                    .foregroundStyle(.secondary)
                TextField("Buscar no fichário", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12 * scale))
            }
            .padding(.horizontal, 8 * scale)
            .padding(.vertical, 4 * scale)
            .background(Capsule().fill(Color.primary.opacity(0.07)))

            if filtered.isEmpty {
                VStack(spacing: 6 * scale) {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 26 * scale))
                        .foregroundStyle(.tertiary)
                    Text(store.archived.isEmpty
                        ? "Pilhas arquivadas e ações em massa aparecem aqui"
                        : "Nada encontrado")
                        .font(.system(size: 11 * scale))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4 * scale) {
                        ForEach(filtered) { entry in
                            row(entry)
                        }
                    }
                }
            }
        }
        .padding(10 * scale)
    }

    private func row(_ entry: ArchivedStack) -> some View {
        HStack(spacing: 8 * scale) {
            ZStack(alignment: .leading) {
                ForEach(Array(entry.urls.prefix(3).enumerated()), id: \.offset) { index, url in
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                        .frame(width: 20 * scale, height: 20 * scale)
                        .padding(.leading, CGFloat(index) * 5 * scale)
                        .rotationEffect(.degrees(Double(index) * 3 - 3))
                }
            }
            .frame(width: 34 * scale, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                    .font(.system(size: 11.5 * scale, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 4 * scale) {
                    Text("\(entry.paths.count) docs · \(entry.date.formatted(date: .abbreviated, time: .shortened))")
                    if entry.hadBulkAction {
                        Image(systemName: "sparkles")
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .font(.system(size: 9.5 * scale))
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                panel.restoreArchived(entry)
            } label: {
                Image(systemName: "tray.and.arrow.up")
                    .font(.system(size: 11 * scale))
            }
            .help("Restaurar como pilha ativa")

            Button {
                store.delete(entry.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10 * scale))
                    .foregroundStyle(.secondary)
            }
            .help("Apagar do fichário")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8 * scale)
        .padding(.vertical, 5 * scale)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(entry.hadBulkAction ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.04))
        )
    }
}
