import SwiftUI
import AppKit

struct FileCell: View {
    let item: FileItem
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 5) {
            ThumbnailView(url: item.url)
                .frame(width: 60, height: 60)

            Text(item.name)
                .font(.system(size: 11))
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
        )
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.1), value: isSelected)
        .help(item.name)
    }
}

/// Linha do modo Lista: preview pequeno + nome + tamanho e data.
struct FileRow: View {
    let item: FileItem
    let isSelected: Bool

    private static let sizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    private static let dateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    var body: some View {
        HStack(spacing: 8) {
            ThumbnailView(url: item.url)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
        )
        .contentShape(Rectangle())
        .help(item.name)
    }

    private var detail: String {
        let when = Self.dateFormatter.localizedString(for: item.date, relativeTo: Date())
        if item.isDirectory {
            return "Pasta · \(when)"
        }
        return "\(Self.sizeFormatter.string(fromByteCount: item.size)) · \(when)"
    }
}

/// Linha do modo Minimalista: só o nome, sem fundo, com sombra para
/// continuar legível sobre a tela levemente escurecida.
struct MinimalFileRow: View {
    let item: FileItem
    let isSelected: Bool

    var body: some View {
        Text(item.name)
            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.85))
            .shadow(color: .black.opacity(0.8), radius: 2, y: 1)
            .padding(.vertical, 3)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accentColor.opacity(0.45) : Color.clear)
            )
            .contentShape(Rectangle())
            .help(item.name)
    }
}

struct ThumbnailView: View {
    let url: URL

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .task(id: url) {
            image = await ThumbnailLoader.shared.thumbnail(
                for: url,
                size: CGSize(width: 120, height: 120)
            )
        }
    }
}
