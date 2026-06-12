import SwiftUI
import AppKit

struct FileCell: View {
    let item: FileItem
    let isSelected: Bool
    var scale: CGFloat = 1
    var isHovered: Bool = false

    var body: some View {
        VStack(spacing: 5 * scale) {
            ThumbnailView(url: item.url)
                .frame(width: 60 * scale, height: 60 * scale)

            Text(item.name)
                .font(.system(size: 11 * scale))
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 8 * scale)
        .padding(.horizontal, 4 * scale)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    isSelected
                        ? Color.accentColor.opacity(0.22)
                        : (isHovered ? Color.primary.opacity(0.05) : Color.clear)
                )
        )
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.1), value: isSelected)
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

/// Linha do modo Lista: preview pequeno + nome + tamanho e data.
struct FileRow: View {
    let item: FileItem
    let isSelected: Bool
    var scale: CGFloat = 1
    var isHovered: Bool = false

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
        HStack(spacing: 8 * scale) {
            ThumbnailView(url: item.url)
                .frame(width: 28 * scale, height: 28 * scale)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 12 * scale))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(.system(size: 10 * scale))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)
        }
        .padding(.vertical, 4 * scale)
        .padding(.horizontal, 8 * scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(
                    isSelected
                        ? Color.accentColor.opacity(0.22)
                        : (isHovered ? Color.primary.opacity(0.05) : Color.clear)
                )
        )
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.12), value: isHovered)
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
    var scale: CGFloat = 1
    var isHovered: Bool = false

    var body: some View {
        Text(item.name)
            .font(.system(size: 13 * scale, weight: isSelected ? .semibold : .regular))
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.85))
            .shadow(color: .black.opacity(0.8), radius: 2, y: 1)
            .padding(.vertical, 3 * scale)
            .padding(.horizontal, 10 * scale)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Capsule()
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(0.45)
                            : (isHovered ? Color.white.opacity(0.09) : Color.clear)
                    )
            )
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.12), value: isHovered)
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
