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
