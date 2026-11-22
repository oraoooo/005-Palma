import CoreGraphics
import AppKit

enum PointerMode {
    case idle
    case leftClickOrDrag
    case scroll
    case rightClick
}

/// A snapshot of "why did it just do that" -- handed to the debug view each
/// frame so you can see the tracked points and raw numbers behind each decision.
struct DebugSnapshot {
    let landmarks: HandLandmarks?
    let mode: PointerMode
    let tiDist: CGFloat
    let imDist: CGFloat
    let timDist: CGFloat
    let tiPinched: Bool
    let imPinched: Bool
    let tiMinched: Bool
    let pinchEnter: CGFloat
    let pinchExit: CGFloat
}

/// Turns raw hand landmarks into OS cursor/mouse/scroll events.
///
/// Pinch thresholds use hysteresis (enter closer than exit) so gestures
/// don't flicker on/off right at the boundary. The exact numbers below are
/// starting points -- they WILL need tuning for your hand/camera/lighting;
/// tweak `pinchEnter` / `pinchExit` if clicks feel too sticky or too twitchy.
final class GestureController {

    private let pinchEnter: CGFloat = 0.35
    private let pinchExit: CGFloat = 0.5

    private let cursor = CursorController()
    private let pointFilter = OneEuroPointFilter(minCutoff: 1.2, beta: 0.5)

    private var mode: PointerMode = .idle
    private var tiPinched = false
    private var imPinched = false
    private var tiMinched = false // thumb+index+middle

    private var scrollAnchor: CGPoint?

    /// Mirror the camera's X axis so "move hand right" -> "cursor moves right".
    /// A front camera faces the user, so raw frame X is flipped relative to the
    /// user's own left/right -- flip this if it ever feels backwards on your setup.
    private let mirrorX = true

    private var lastSeenAt: CFTimeInterval = 0
    private let handLostTimeout: CFTimeInterval = 0.4

    /// Called at the end of every update (hand found or not) with the current
    /// distances/mode, so a debug UI can render "what it's thinking" live.
    var onUpdate: ((DebugSnapshot) -> Void)?

    func update(landmarks: HandLandmarks?, timestamp: CFTimeInterval) {
        guard let landmarks else {
            if timestamp - lastSeenAt > handLostTimeout {
                releaseEverything()
            }
            emitSnapshot(landmarks: nil, tiDist: 0, imDist: 0, timDist: 0)
            return
        }
        lastSeenAt = timestamp

        let scale = landmarks.palmScale
        let tiDist = distance(landmarks.thumbTip, landmarks.indexTip) / scale
        let imDist = distance(landmarks.indexTip, landmarks.middleTip) / scale
        let tmDist = distance(landmarks.thumbTip, landmarks.middleTip) / scale
        let timDist = max(tiDist, tmDist)

        tiPinched = hysteresis(current: tiPinched, distance: tiDist)
        imPinched = hysteresis(current: imPinched, distance: imDist)
        tiMinched = hysteresis(current: tiMinched, distance: timDist)

        let desiredMode: PointerMode
        if tiMinched {
            desiredMode = .rightClick
        } else if imPinched {
            desiredMode = .scroll
        } else if tiPinched {
            desiredMode = .leftClickOrDrag
        } else {
            desiredMode = .idle
        }

        let screenPoint = mapToScreen(landmarks.indexTip)

        if desiredMode != mode {
            exitMode(mode, at: screenPoint)
            enterMode(desiredMode, at: screenPoint)
            mode = desiredMode
        }

        drive(mode: mode, landmarks: landmarks, screenPoint: screenPoint, timestamp: timestamp)
        emitSnapshot(landmarks: landmarks, tiDist: tiDist, imDist: imDist, timDist: timDist)
    }

    private func emitSnapshot(landmarks: HandLandmarks?, tiDist: CGFloat, imDist: CGFloat, timDist: CGFloat) {
        onUpdate?(DebugSnapshot(
            landmarks: landmarks,
            mode: mode,
            tiDist: tiDist,
            imDist: imDist,
            timDist: timDist,
            tiPinched: tiPinched,
            imPinched: imPinched,
            tiMinched: tiMinched,
            pinchEnter: pinchEnter,
            pinchExit: pinchExit
        ))
    }

    private func hysteresis(current: Bool, distance: CGFloat) -> Bool {
        current ? distance < pinchExit : distance < pinchEnter
    }

    private func enterMode(_ mode: PointerMode, at point: CGPoint) {
        switch mode {
        case .idle:
            break
        case .leftClickOrDrag:
            pointFilter.reset()
            cursor.leftMouseDown(at: point)
        case .scroll:
            scrollAnchor = nil // established lazily in drive(), against the same metric (finger midpoint) used each frame
        case .rightClick:
            cursor.rightMouseDown(at: point)
        }
    }

    private func exitMode(_ mode: PointerMode, at point: CGPoint) {
        switch mode {
        case .idle:
            break
        case .leftClickOrDrag:
            cursor.leftMouseUp(at: point)
        case .scroll:
            scrollAnchor = nil
        case .rightClick:
            cursor.rightMouseUp(at: point)
        }
    }

    private func drive(mode: PointerMode, landmarks: HandLandmarks, screenPoint: CGPoint, timestamp: CFTimeInterval) {
        switch mode {
        case .idle:
            cursor.moveTo(screenPoint)

        case .leftClickOrDrag:
            cursor.leftMouseDragged(to: screenPoint)

        case .scroll:
            let midpoint = CGPoint(
                x: (landmarks.indexTip.x + landmarks.middleTip.x) / 2,
                y: (landmarks.indexTip.y + landmarks.middleTip.y) / 2
            )
            let midpointScreen = rawToScreen(midpoint)
            guard let anchor = scrollAnchor else {
                scrollAnchor = midpointScreen // first frame in scroll mode: just establish the baseline
                return
            }
            let dx = Int32((midpointScreen.x - anchor.x) * 2)
            let dy = Int32((anchor.y - midpointScreen.y) * 2) // screen Y grows downward; invert for "natural" scroll
            if dx != 0 || dy != 0 {
                cursor.scroll(dx: dx, dy: dy)
            }
            scrollAnchor = midpointScreen

        case .rightClick:
            break // momentary tap: no continuous action while held
        }
    }

    private func releaseEverything() {
        guard mode != .idle else { return }
        exitMode(mode, at: cursor.currentLocation)
        mode = .idle
        tiPinched = false
        imPinched = false
        tiMinched = false
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }

    /// Smoothed cursor position, driven only by the index fingertip (idle / click-drag modes).
    /// Uses `pointFilter`, which must not be fed any other signal (e.g. the scroll midpoint) --
    /// mixing sources through one filter's history causes a jump whenever gestures switch.
    private func mapToScreen(_ visionPoint: CGPoint) -> CGPoint {
        let smoothed = pointFilter.filter(visionPoint, timestamp: CACurrentMediaTime())
        return rawToScreen(smoothed)
    }

    /// Vision space (origin bottom-left, 0...1) -> CoreGraphics display space (origin top-left, pixels).
    /// No smoothing here -- used for signals (like the scroll midpoint) that only care about
    /// frame-to-frame delta, not absolute jitter-free position.
    private func rawToScreen(_ visionPoint: CGPoint) -> CGPoint {
        let bounds = CGDisplayBounds(CGMainDisplayID())
        let normalizedX = mirrorX ? (1 - visionPoint.x) : visionPoint.x
        let x = bounds.origin.x + normalizedX * bounds.width
        let y = bounds.origin.y + (1 - visionPoint.y) * bounds.height
        return CGPoint(x: x, y: y)
    }
}
