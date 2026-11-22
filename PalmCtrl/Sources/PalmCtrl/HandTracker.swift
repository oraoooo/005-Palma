import Vision
import CoreVideo

/// The subset of hand landmarks PalmCtrl's gestures need.
/// Points are in Vision's normalized space: origin bottom-left, 0...1 on both axes.
struct HandLandmarks {
    let wrist: CGPoint
    let thumbTip: CGPoint
    let indexTip: CGPoint
    let indexMCP: CGPoint
    let middleTip: CGPoint
    let middleMCP: CGPoint

    /// A roughly pose-invariant measure of "how big is the hand in this frame",
    /// used to turn absolute pixel distances into scale-independent pinch thresholds.
    var palmScale: CGFloat {
        let dx = indexMCP.x - wrist.x
        let dy = indexMCP.y - wrist.y
        return max(sqrt(dx * dx + dy * dy), 0.001)
    }
}

final class HandTracker {

    private let request = VNDetectHumanHandPoseRequest()

    init() {
        request.maximumHandCount = 1
    }

    /// Runs hand-pose detection on one frame. Returns nil if no confident hand is found.
    func detect(in pixelBuffer: CVPixelBuffer) -> HandLandmarks? {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observation = request.results?.first else { return nil }

        do {
            let points = try observation.recognizedPoints(.all)

            func point(_ key: VNHumanHandPoseObservation.JointName, minConfidence: Float = 0.3) -> CGPoint? {
                guard let p = points[key], p.confidence >= minConfidence else { return nil }
                return CGPoint(x: p.location.x, y: p.location.y)
            }

            guard
                let wrist = point(.wrist),
                let thumbTip = point(.thumbTip),
                let indexTip = point(.indexTip),
                let indexMCP = point(.indexMCP),
                let middleTip = point(.middleTip),
                let middleMCP = point(.middleMCP)
            else { return nil }

            return HandLandmarks(
                wrist: wrist,
                thumbTip: thumbTip,
                indexTip: indexTip,
                indexMCP: indexMCP,
                middleTip: middleTip,
                middleMCP: middleMCP
            )
        } catch {
            return nil
        }
    }
}
