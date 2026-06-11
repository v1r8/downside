import AppKit

/// Detecta quando o mouse permanece no canto configurado da tela.
/// Usa um timer leve de polling (~16x/s) em vez de event taps,
/// o que dispensa permissões de acessibilidade e custa quase nada de CPU.
final class HotCornerMonitor {
    var onTrigger: ((NSScreen, HotCorner) -> Void)?

    private var timer: Timer?
    private var dwellStart: Date?
    private var dwellCorner: HotCorner?
    /// Evita redisparo contínuo: só rearma depois que o mouse sai do canto.
    private var armed = true

    func start() {
        stop()
        let timer = Timer(timeInterval: 0.06, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        dwellStart = nil
    }

    private func tick() {
        guard Prefs.hotCornerEnabled else {
            dwellStart = nil
            return
        }

        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) else {
            return
        }

        let corners = Prefs.corners
        // Durante um arrasto (de qualquer app), a zona do canto fica
        // maior e o painel abre mais rápido, para facilitar soltar
        // direto nas pilhas.
        let dragging = NSEvent.pressedMouseButtons != 0
        let zoneSize: CGFloat = dragging ? 28 : 6
        if let corner = corners.first(where: { $0.zone(in: screen.frame, size: zoneSize).contains(mouse) }) {
            guard armed else { return }
            let threshold = dragging ? min(0.2, Prefs.dwell) : Prefs.dwell
            if dwellCorner == corner, let start = dwellStart {
                if Date().timeIntervalSince(start) >= threshold {
                    dwellStart = nil
                    dwellCorner = nil
                    armed = false
                    onTrigger?(screen, corner)
                }
            } else {
                dwellCorner = corner
                dwellStart = Date()
            }
        } else {
            dwellStart = nil
            dwellCorner = nil
            armed = true
        }
    }
}
