import CoreGraphics
import ApplicationServices

/// Thin wrapper around CGEvent for moving the real OS cursor and
/// synthesizing mouse buttons / scroll, mirroring how a trackpad
/// would report the same gestures.
final class CursorController {

    static func hasAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    private let source = CGEventSource(stateID: .hidSystemState)
    private var isLeftButtonDown = false
    private var isRightButtonDown = false

    var currentLocation: CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    /// Plain cursor move (button up). Used in "no gesture" mode.
    func moveTo(_ point: CGPoint) {
        guard let event = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) else { return }
        event.post(tap: .cghidEventTap)
    }

    func leftMouseDown(at point: CGPoint) {
        isLeftButtonDown = true
        post(.leftMouseDown, at: point, button: .left)
    }

    /// Dragged move, used while the left button is held (makes click-and-drag register correctly).
    func leftMouseDragged(to point: CGPoint) {
        post(.leftMouseDragged, at: point, button: .left)
    }

    func leftMouseUp(at point: CGPoint) {
        isLeftButtonDown = false
        post(.leftMouseUp, at: point, button: .left)
    }

    func rightMouseDown(at point: CGPoint) {
        isRightButtonDown = true
        post(.rightMouseDown, at: point, button: .right)
    }

    func rightMouseUp(at point: CGPoint) {
        isRightButtonDown = false
        post(.rightMouseUp, at: point, button: .right)
    }

    /// Posts a scroll-wheel event. Positive dy scrolls content up (matches trackpad "natural" scrolling).
    func scroll(dx: Int32, dy: Int32) {
        guard let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0) else { return }
        event.post(tap: .cghidEventTap)
    }

    /// Safety net: release any button PalmCtrl left down (e.g. on exit or hand loss).
    func releaseAllButtons(at point: CGPoint) {
        if isLeftButtonDown { leftMouseUp(at: point) }
        if isRightButtonDown { rightMouseUp(at: point) }
    }

    private func post(_ type: CGEventType, at point: CGPoint, button: CGMouseButton) {
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: button) else { return }
        event.post(tap: .cghidEventTap)
    }
}
