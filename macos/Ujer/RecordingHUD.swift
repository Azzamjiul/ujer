import AppKit

@MainActor
final class RecordingHUD {
    private let panel: NSPanel
    private let view: RecordingHUDView
    private let level: () -> CGFloat
    private var timer: Timer?
    private var startedAt: Date?
    private var hasPositioned = false

    init(level: @escaping () -> CGFloat, onStop: @escaping () -> Void) {
        self.level = level
        view = RecordingHUDView(frame: NSRect(x: 0, y: 0, width: 280, height: 58))
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 58),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = view
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        view.onStop = onStop
    }

    func show() {
        startedAt = Date()
        view.resetWaveform()
        if !hasPositioned, let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.minY + 56))
            hasPositioned = true
        }
        panel.orderFrontRegardless()
        timer?.invalidate()
        timer = Timer(timeInterval: 1 / 15, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.update()
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
        update()
    }

    func showResult(_ message: String) {
        timer?.invalidate()
        startedAt = nil
        view.resultMessage = message
        view.needsDisplay = true
        panel.orderFrontRegardless()

        let dismissTimer = Timer(timeInterval: 2.5, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.hide()
            }
        }
        timer = dismissTimer
        RunLoop.main.add(dismissTimer, forMode: .common)
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        panel.orderOut(nil)
    }

    private func update() {
        guard let startedAt else { return }
        view.elapsed = Date().timeIntervalSince(startedAt)
        view.append(level: level())
        view.needsDisplay = true
    }
}

@MainActor
private final class RecordingHUDView: NSView {
    var elapsed: TimeInterval = 0
    var onStop: (() -> Void)?
    var resultMessage: String?

    private let stopRect = NSRect(x: 235, y: 11, width: 36, height: 36)
    private var dragStart: (mouse: NSPoint, panel: NSPoint)?
    private var levels = Array(repeating: CGFloat.zero, count: 28)

    func resetWaveform() {
        resultMessage = nil
        levels = Array(repeating: 0, count: levels.count)
    }

    func append(level: CGFloat) {
        levels.removeFirst()
        levels.append(level)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.13, alpha: 0.96).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 18, yRadius: 18).fill()

        if let resultMessage {
            drawResult(resultMessage)
            return
        }

        let timerText = String(format: "%d:%02d", Int(elapsed) / 60, Int(elapsed) % 60)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        timerText.draw(at: NSPoint(x: 177, y: 21), withAttributes: attributes)

        let centerY = bounds.midY
        let baseline = NSBezierPath()
        baseline.move(to: NSPoint(x: 16, y: centerY))
        baseline.line(to: NSPoint(x: 158, y: centerY))
        baseline.lineWidth = 1
        NSColor.white.withAlphaComponent(0.35).setStroke()
        baseline.stroke()

        for (index, level) in levels.enumerated() where level > 0 {
            let height = 4 + 34 * sqrt(level)
            let rect = NSRect(x: 16 + CGFloat(index) * 5.2, y: centerY - height / 2, width: 2.6, height: height)
            NSColor.white.withAlphaComponent(0.9).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1.3, yRadius: 1.3).fill()
        }

        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: stopRect).fill()
        let square = NSRect(x: stopRect.midX - 5, y: stopRect.midY - 5, width: 10, height: 10)
        NSColor.white.setFill()
        NSBezierPath(roundedRect: square, xRadius: 2, yRadius: 2).fill()
    }

    private func drawResult(_ message: String) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let textSize = (message as NSString).size(withAttributes: attributes)
        let contentWidth = 22 + 10 + textSize.width
        let startX = (bounds.width - contentWidth) / 2
        let checkRect = NSRect(x: startX, y: bounds.midY - 11, width: 22, height: 22)

        NSColor.systemGreen.setFill()
        NSBezierPath(ovalIn: checkRect).fill()
        let check = NSBezierPath()
        check.move(to: NSPoint(x: checkRect.minX + 5, y: checkRect.midY))
        check.line(to: NSPoint(x: checkRect.minX + 9, y: checkRect.midY - 4))
        check.line(to: NSPoint(x: checkRect.minX + 17, y: checkRect.midY + 5))
        check.lineWidth = 2
        NSColor.white.setStroke()
        check.stroke()

        (message as NSString).draw(
            at: NSPoint(x: startX + 32, y: (bounds.height - textSize.height) / 2),
            withAttributes: attributes
        )
    }

    override func mouseDown(with event: NSEvent) {
        guard resultMessage == nil else { return }
        if stopRect.contains(convert(event.locationInWindow, from: nil)) {
            onStop?()
        } else if let panel = window {
            dragStart = (NSEvent.mouseLocation, panel.frame.origin)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart, let panel = window else { return }
        let mouse = NSEvent.mouseLocation
        panel.setFrameOrigin(NSPoint(
            x: dragStart.panel.x + mouse.x - dragStart.mouse.x,
            y: dragStart.panel.y + mouse.y - dragStart.mouse.y
        ))
    }

    override func mouseUp(with event: NSEvent) {
        dragStart = nil
    }
}
