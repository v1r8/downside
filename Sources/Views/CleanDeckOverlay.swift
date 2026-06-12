import SwiftUI
import AppKit

/// Animação da limpeza: as cartas dos arquivos antigos voam de suas
/// posições para um deck no centro, dão uma embaralhada brincalhona e
/// somem num "puff" — então os arquivos vão para o Lixo e o que sobra
/// reflui na lista.
struct CleanDeckOverlay: View {
    /// (url, posição de origem no espaço do grid)
    let cards: [(url: URL, from: CGPoint)]
    let center: CGPoint
    let scale: CGFloat
    var onDone: () -> Void

    /// 0 = nas posições originais · 1 = reunidas no deck ·
    /// 2 = embaralhando · 3 = puff
    @State private var phase = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                ThumbnailView(url: card.url)
                    .frame(width: 44 * scale, height: 44 * scale)
                    .rotationEffect(rotation(for: index))
                    .animation(
                        phase == 2
                            ? .easeInOut(duration: 0.09).repeatCount(7, autoreverses: true)
                            : .spring(response: 0.4, dampingFraction: 0.75)
                                .delay(Double(index) * 0.035),
                        value: phase
                    )
                    .scaleEffect(phase >= 3 ? 0.05 : 1)
                    .opacity(phase >= 3 ? 0 : 1)
                    .position(position(for: index, card: card))
                    .animation(
                        .spring(response: 0.42, dampingFraction: 0.78)
                            .delay(Double(index) * 0.035),
                        value: phase
                    )
            }
        }
        .allowsHitTesting(false)
        .onAppear { runSequence() }
    }

    private func position(for index: Int, card: (url: URL, from: CGPoint)) -> CGPoint {
        guard phase >= 1 else { return card.from }
        return CGPoint(
            x: center.x + CGFloat(index % 5 - 2) * 2 * scale,
            y: center.y - CGFloat(index) * 1.5 * scale
        )
    }

    private func rotation(for index: Int) -> Angle {
        switch phase {
        case 0: return .degrees(0)
        case 1: return .degrees(Double(index % 7) * 3 - 9)
        case 2: return .degrees(Double(index % 2 == 0 ? 10 : -10))
        default: return .degrees(Double(index % 7) * 14 - 42)
        }
    }

    private func runSequence() {
        Task { @MainActor in
            // Reúne as cartas no deck.
            phase = 1
            try? await Task.sleep(nanoseconds: 650_000_000)
            // Embaralha / fidget.
            phase = 2
            try? await Task.sleep(nanoseconds: 750_000_000)
            // Puff.
            phase = 3
            try? await Task.sleep(nanoseconds: 420_000_000)
            onDone()
        }
    }
}
