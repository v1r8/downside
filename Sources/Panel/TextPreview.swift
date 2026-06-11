import SwiftUI
import AppKit

/// Ponte para comandar o NSTextView do preview (desfazer, refazer,
/// formatação Markdown e busca interna).
@MainActor
final class TextEditorController: ObservableObject {
    weak var textView: NSTextView?

    func undo() {
        textView?.undoManager?.undo()
    }

    func redo() {
        textView?.undoManager?.redo()
    }

    /// Envolve a seleção com um marcador Markdown (** ou *).
    /// Registrado no undo via insertText.
    func wrapSelection(with marker: String) {
        guard let textView else { return }
        let range = textView.selectedRange()
        let selected = (textView.string as NSString).substring(with: range)
        let replacement = marker + selected + marker
        guard textView.shouldChangeText(in: range, replacementString: replacement) else { return }
        textView.insertText(replacement, replacementRange: range)
        textView.setSelectedRange(NSRange(location: range.location + marker.count, length: range.length))
        textView.window?.makeFirstResponder(textView)
    }

    /// Busca a próxima ocorrência a partir da seleção atual (com volta
    /// ao início), seleciona e rola até ela.
    func findNext(_ query: String) {
        guard let textView, !query.isEmpty else { return }
        let content = textView.string as NSString
        let start = NSMaxRange(textView.selectedRange())
        var found = content.range(
            of: query,
            options: [.caseInsensitive],
            range: NSRange(location: start, length: content.length - start)
        )
        if found.location == NSNotFound {
            found = content.range(of: query, options: [.caseInsensitive])
        }
        guard found.location != NSNotFound else { return }
        textView.setSelectedRange(found)
        textView.scrollRangeToVisible(found)
        textView.showFindIndicator(for: found)
    }
}

/// NSTextView com undo nativo, ligado a um Binding<String>.
struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String
    let fontSize: CGFloat
    let controller: TextEditorController

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let textView = scroll.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 6, height: 8)
        scroll.drawsBackground = false
        textView.string = text
        controller.textView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        controller.textView = textView
        textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        // Só sobrescreve se a mudança veio de fora (nunca durante edição).
        if textView.string != text, textView.window?.firstResponder !== textView {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

/// Preview de texto: toolbar em vidro (desfazer/refazer, negrito e
/// itálico Markdown, busca) + editor com salvamento automático.
struct TextFilePreview: View {
    let url: URL
    let scale: CGFloat
    let sizeFactor: CGFloat

    @StateObject private var controller = TextEditorController()
    @State private var text = ""
    @State private var loaded = false
    @State private var lastSaved = ""
    @State private var status = ""
    @State private var searchQuery = ""
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 6 * scale) {
            toolbar

            PlainTextEditor(text: $text, fontSize: 12 * scale, controller: controller)
                .frame(height: 260 * scale * sizeFactor)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(status.isEmpty ? "Salvamento automático · ⌘Z desfaz, ⇧⌘Z refaz" : status)
                .font(.system(size: 9 * scale))
                .foregroundStyle(.secondary)
        }
        .onAppear(perform: load)
        .onChange(of: text) { _, newValue in
            // Só salva mudanças reais de conteúdo (nunca scroll/redraws).
            guard loaded, newValue != lastSaved else { return }
            scheduleSave(newValue)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 2 * scale) {
            toolbarButton("arrow.uturn.backward", help: "Desfazer (⌘Z)") {
                controller.undo()
            }
            toolbarButton("arrow.uturn.forward", help: "Refazer (⇧⌘Z)") {
                controller.redo()
            }

            toolbarDivider

            toolbarButton("bold", help: "Negrito (Markdown **texto**)") {
                controller.wrapSelection(with: "**")
            }
            toolbarButton("italic", help: "Itálico (Markdown *texto*)") {
                controller.wrapSelection(with: "*")
            }

            toolbarDivider

            HStack(spacing: 3 * scale) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 9 * scale))
                    .foregroundStyle(.secondary)
                TextField("Buscar no texto", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10.5 * scale))
                    .onSubmit { controller.findNext(searchQuery) }
                if !searchQuery.isEmpty {
                    Button {
                        controller.findNext(searchQuery)
                    } label: {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 10 * scale))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Próxima ocorrência (Return)")
                }
            }
            .padding(.horizontal, 7 * scale)
            .padding(.vertical, 3 * scale)
            .background(Capsule().fill(Color.primary.opacity(0.07)))
        }
        .padding(5 * scale)
        .background(toolbarBackground)
    }

    private func toolbarButton(
        _ systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11 * scale, weight: .medium))
                .frame(width: 22 * scale, height: 20 * scale)
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 14 * scale)
            .padding(.horizontal, 3 * scale)
    }

    /// Vidro nativo no Tahoe (Xcode 26+); material translúcido como
    /// fallback em SDKs anteriores.
    @ViewBuilder
    private var toolbarBackground: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: .rect(cornerRadius: 10))
        } else {
            legacyToolbarBackground
        }
        #else
        legacyToolbarBackground
        #endif
    }

    private var legacyToolbarBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }

    private func load() {
        guard !loaded else { return }
        let content = (try? String(contentsOf: url, encoding: .utf8))
            ?? (try? String(contentsOf: url, encoding: .isoLatin1))
            ?? ""
        text = content
        lastSaved = content
        loaded = true
    }

    private func scheduleSave(_ value: String) {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            do {
                try value.write(to: url, atomically: true, encoding: .utf8)
                lastSaved = value
                status = "Salvo ✓"
            } catch {
                status = "Não foi possível salvar"
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if !Task.isCancelled { status = "" }
        }
    }
}
