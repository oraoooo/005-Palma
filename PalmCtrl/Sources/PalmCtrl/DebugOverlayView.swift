import AppKit
import CoreImage
import CoreVideo

/// Shows the camera feed with the tracked hand skeleton, live pinch
/// distances, and the current gesture mode drawn on top -- so you can see
/// exactly what PalmCtrl is seeing and why it did (or didn't) click.
final class DebugOverlayView: NSView {

    private let ciContext = CIContext()
    private var latestImage: CGImage?
    private var latestSnapshot: DebugSnapshot?

    // Deliberately left non-flipped (NSView's default: origin bottom-left, y grows
    // upward). That's ALSO Vision's own point convention, so landmark coordinates
    // need no y-flip at all here -- and CGContext.draw(image:in:) only renders
    // right-side-up in a non-flipped context. (Flipping this view and trying to
    // compensate is the classic way to end up with an upside-down image.)

    func present(pixelBuffer: CVPixelBuffer, snapshot: DebugSnapshot) {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        latestImage = ciContext.createCGImage(ciImage, from: ciImage.extent)
        latestSnapshot = snapshot
        setNeedsDisplay(bounds)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        if let image = latestImage {
            // The one deliberate mirror (selfie-style), applied only to this draw
            // call so it doesn't affect the skeleton/text drawn below.
            context.saveGState()
            context.translateBy(x: bounds.width, y: 0)
            context.scaleBy(x: -1, y: 1)
            context.draw(image, in: bounds)
            context.restoreGState()
        }

        guard let snapshot = latestSnapshot else { return }
        drawSkeleton(snapshot, in: context)
        drawHUD(snapshot)
    }

    // MARK: - Skeleton

    /// Vision space (origin bottom-left, 0...1) -> this view's space (also
    /// origin bottom-left, pixels). Only x is mirrored, matching the image mirror
    /// above and the same mirroring GestureController applies to the real cursor --
    /// so a dot here lines up with both the picture and what actually drives the mouse.
    private func toView(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (1 - p.x) * bounds.width, y: p.y * bounds.height)
    }

    private func drawSkeleton(_ snapshot: DebugSnapshot, in context: CGContext) {
        guard let lm = snapshot.landmarks else { return }

        func dot(_ p: CGPoint, color: NSColor, radius: CGFloat = 7) {
            let v = toView(p)
            context.setFillColor(color.cgColor)
            context.fillEllipse(in: CGRect(x: v.x - radius / 2, y: v.y - radius / 2, width: radius, height: radius))
        }

        func line(_ a: CGPoint, _ b: CGPoint, color: NSColor) {
            let va = toView(a), vb = toView(b)
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(2)
            context.move(to: va)
            context.addLine(to: vb)
            context.strokePath()
        }

        let bones = NSColor.white.withAlphaComponent(0.6)
        line(lm.wrist, lm.indexMCP, color: bones)
        line(lm.wrist, lm.middleMCP, color: bones)
        line(lm.indexMCP, lm.indexTip, color: bones)
        line(lm.middleMCP, lm.middleTip, color: bones)

        // The three gesture-relevant links, colored by whether they're currently "pinched".
        line(lm.thumbTip, lm.indexTip, color: snapshot.tiPinched ? .systemGreen : .systemYellow)
        line(lm.indexTip, lm.middleTip, color: snapshot.imPinched ? .systemGreen : .systemYellow)
        line(lm.thumbTip, lm.middleTip, color: snapshot.tiMinched ? .systemGreen : .systemYellow)

        dot(lm.wrist, color: .white)
        dot(lm.thumbTip, color: .systemOrange, radius: 10)
        dot(lm.indexTip, color: .systemRed, radius: 12) // this one drives the cursor
        dot(lm.middleTip, color: .systemBlue, radius: 10)
    }

    // MARK: - HUD text

    private func drawHUD(_ snapshot: DebugSnapshot) {
        let lines: [String] = [
            "mode: \(modeLabel(snapshot.mode))",
            String(format: "thumb-index  %.2f  (pinch <%.2f, release >%.2f)  %@",
                   snapshot.tiDist, snapshot.pinchEnter, snapshot.pinchExit, snapshot.tiPinched ? "PINCHED" : "-"),
            String(format: "index-middle %.2f  %@", snapshot.imDist, snapshot.imPinched ? "PINCHED" : "-"),
            String(format: "3-finger     %.2f  %@", snapshot.timDist, snapshot.tiMinched ? "PINCHED" : "-"),
            snapshot.landmarks == nil ? "NO HAND DETECTED" : ""
        ]

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.white,
            .strokeColor: NSColor.black,
            .strokeWidth: -3
        ]

        var y: CGFloat = bounds.height - 24 // start near the top; y grows upward in this view
        for line in lines where !line.isEmpty {
            (line as NSString).draw(at: CGPoint(x: 12, y: y), withAttributes: attrs)
            y -= 20
        }
    }

    private func modeLabel(_ mode: PointerMode) -> String {
        switch mode {
        case .idle: return "idle (following finger)"
        case .leftClickOrDrag: return "LEFT CLICK / DRAG"
        case .scroll: return "SCROLL"
        case .rightClick: return "RIGHT CLICK"
        }
    }
}

/// Owns the debug window so main.swift just creates one of these and feeds it frames.
final class DebugWindowController {
    let window: NSWindow
    let view = DebugOverlayView()

    init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PalmCtrl -- debug view"
        window.contentView = view
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func present(pixelBuffer: CVPixelBuffer, snapshot: DebugSnapshot) {
        view.present(pixelBuffer: pixelBuffer, snapshot: snapshot)
    }
}
