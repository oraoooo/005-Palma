import Foundation

/// Low-jitter, low-lag signal smoother (Casiez et al., "1€ Filter").
/// Used to smooth the raw, noisy fingertip position before it drives the cursor.
final class OneEuroFilter {

    private var freq: Double
    private let minCutoff: Double
    private let beta: Double
    private let dCutoff: Double

    private var xPrev: Double?
    private var dxPrev: Double = 0
    private var lastTimestamp: CFTimeInterval?

    init(freq: Double = 60, minCutoff: Double = 1.0, beta: Double = 0.4, dCutoff: Double = 1.0) {
        self.freq = freq
        self.minCutoff = minCutoff
        self.beta = beta
        self.dCutoff = dCutoff
    }

    private func alpha(_ cutoff: Double) -> Double {
        let te = 1.0 / freq
        let tau = 1.0 / (2 * Double.pi * cutoff)
        return 1.0 / (1.0 + tau / te)
    }

    func filter(_ x: Double, timestamp: CFTimeInterval) -> Double {
        if let last = lastTimestamp {
            let dt = timestamp - last
            if dt > 0 { freq = 1.0 / dt }
        }
        lastTimestamp = timestamp

        let dx = xPrev != nil ? (x - xPrev!) * freq : 0
        let edx = dxPrev + alpha(dCutoff) * (dx - dxPrev)
        dxPrev = edx

        let cutoff = minCutoff + beta * abs(edx)
        let a = alpha(cutoff)
        let result = xPrev != nil ? xPrev! + a * (x - xPrev!) : x
        xPrev = result
        return result
    }

    func reset() {
        xPrev = nil
        dxPrev = 0
        lastTimestamp = nil
    }
}

/// Convenience wrapper that smooths a 2D point.
final class OneEuroPointFilter {
    private let xFilter: OneEuroFilter
    private let yFilter: OneEuroFilter

    init(minCutoff: Double = 1.0, beta: Double = 0.4) {
        xFilter = OneEuroFilter(minCutoff: minCutoff, beta: beta)
        yFilter = OneEuroFilter(minCutoff: minCutoff, beta: beta)
    }

    func filter(_ point: CGPoint, timestamp: CFTimeInterval) -> CGPoint {
        CGPoint(
            x: xFilter.filter(point.x, timestamp: timestamp),
            y: yFilter.filter(point.y, timestamp: timestamp)
        )
    }

    func reset() {
        xFilter.reset()
        yFilter.reset()
    }
}
