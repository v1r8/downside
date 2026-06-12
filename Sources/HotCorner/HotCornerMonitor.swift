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
    /// changeCount do pasteboard de arrasto enquanto nenhum botão está
    /// pressionado — referência para saber se um arrasto DE VERDADE
    /// começou (clicar e segurar sem arrastar nada não conta).
    private var idleDragCount = NSPasteboard(name: .drag).changeCount

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

        let frame = screen.frame
        let corners = Prefs.corners
        let edges = Prefs.edges

        // Arrasto REAL: botão pressionado E o pasteboard de arrasto
        // ganhou conteúdo desde o último momento ocioso. Clicar e
        // segurar (seleção de texto etc.) não abre o painel.
        let buttons = NSEvent.pressedMouseButtons
        let dragPasteboard = NSPasteboard(name: .drag)
        if buttons == 0 {
            idleDragCount = dragPasteboard.changeCount
        }
        let dragging = buttons != 0 && dragPasteboard.changeCount != idleDragCount

        // Cantos têm prioridade; laterais (se ativadas) abrem ancorando
        // no canto mais próximo da metade da tela em que o mouse está.
        // Durante um arrasto vale um raio configurável, para o painel
        // abrir antes de encostar.
        var active: HotCorner?
        if dragging {
            let radius = Prefs.dragOpenRadius
            active = corners.first { corner in
                let point = corner.point(in: frame)
                let dx = mouse.x - point.x
                let dy = mouse.y - point.y
                return (dx * dx + dy * dy).squareRoot() <= radius
            }
            if active == nil {
                // Laterais ignoram a faixa próxima dos cantos, para não
                // conflitar com os gatilhos de canto.
                let insideBand = mouse.y > frame.minY + 120 && mouse.y < frame.maxY - 120
                if edges.contains(.left), insideBand, mouse.x - frame.minX <= radius {
                    active = mouse.y < frame.midY ? .bottomLeft : .topLeft
                } else if edges.contains(.right), insideBand, frame.maxX - mouse.x <= radius {
                    active = mouse.y < frame.midY ? .bottomRight : .topRight
                }
            }
        } else {
            active = corners.first { $0.zone(in: frame, size: 6).contains(mouse) }
            if active == nil {
                let insideBand = mouse.y > frame.minY + 120 && mouse.y < frame.maxY - 120
                if edges.contains(.left), insideBand, mouse.x <= frame.minX + 2 {
                    active = mouse.y < frame.midY ? .bottomLeft : .topLeft
                } else if edges.contains(.right), insideBand, mouse.x >= frame.maxX - 2 {
                    active = mouse.y < frame.midY ? .bottomRight : .topRight
                }
            }
        }

        if let corner = active {
            guard armed else { return }
            let threshold = dragging ? 0.05 : Prefs.dwell
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
