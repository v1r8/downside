import AppKit

/// Detecta quando o mouse permanece no canto configurado da tela.
/// Usa um timer leve de polling (~16x/s) em vez de event taps,
/// o que dispensa permissões de acessibilidade e custa quase nada de CPU.
final class HotCornerMonitor {
    var onTrigger: ((NSScreen) -> Void)?

    private var timer: Timer?
    private var dwellStart: Date?
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

        let zone = Prefs.corner.zone(in: screen.frame, size: 6)
        if zone.contains(mouse) {
            guard armed else { return }
            if let start = dwellStart {
                if Date().timeIntervalSince(start) >= Prefs.dwell {
                    dwellStart = nil
                    armed = false
                    onTrigger?(screen)
                }
            } else {
                dwellStart = Date()
            }
        } else {
            dwellStart = nil
            armed = true
        }
    }
}
