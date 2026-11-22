import AVFoundation
import CoreVideo

/// Wraps an AVCaptureSession on the front camera and delivers raw frames.
final class CameraCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "palmctrl.camera.queue")
    private let onFrame: (CVPixelBuffer, CFTimeInterval) -> Void

    init(onFrame: @escaping (CVPixelBuffer, CFTimeInterval) -> Void) {
        self.onFrame = onFrame
        super.init()
    }

    static func requestAccess(_ completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        default:
            completion(false)
        }
    }

    func start() {
        queue.async { [weak self] in
            self?.configureAndRun()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.session.stopRunning()
        }
    }

    private func configureAndRun() {
        session.beginConfiguration()
        session.sessionPreset = .vga640x480

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input) else {
            print("[Camera] No usable camera found.")
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)

        guard session.canAddOutput(output) else {
            print("[Camera] Could not add video output.")
            session.commitConfiguration()
            return
        }
        session.addOutput(output)

        // Deliver the raw, unmirrored sensor image. AVFoundation auto-mirrors
        // front cameras by default, and `automaticallyAdjustsVideoMirroring`
        // must be turned off *before* `isVideoMirrored` has any effect --
        // setting isVideoMirrored alone (as before) was silently ignored.
        // PalmCtrl applies its own single, deliberate mirror in GestureController
        // and DebugOverlayView; mirroring here too would double it up.
        if let connection = output.connection(with: .video) {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }

        session.commitConfiguration()
        session.startRunning()
        print("[Camera] Running on \(device.localizedName).")
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = CACurrentMediaTime()
        onFrame(pixelBuffer, timestamp)
    }
}
