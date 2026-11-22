import Foundation
import AppKit

print("""
PalmCtrl (MVP)
  - Index finger moves the cursor
  - Pinch thumb+index  -> click / long-click / drag
  - Pinch index+middle -> scroll
  - Pinch thumb+index+middle -> right-click
  A debug window will open showing the camera feed, tracked hand skeleton,
  and live pinch distances/mode -- use it to tune thresholds.
  Ctrl+C to quit.
""")

let app = NSApplication.shared
app.setActivationPolicy(.regular)

guard CursorController.hasAccessibilityPermission() else {
    print("""
    [Permission] PalmCtrl needs Accessibility access to move the cursor.
    A system prompt should have just appeared -- grant it to your terminal app,
    then re-run PalmCtrl.
    """)
    exit(1)
}

let tracker = HandTracker()
let gestures = GestureController()
let debugWindow = DebugWindowController()

var latestSnapshot: DebugSnapshot?
gestures.onUpdate = { snapshot in latestSnapshot = snapshot }

// Held at global scope so ARC doesn't tear down the capture session once
// the permission-request closure below returns.
var camera: CameraCapture?

CameraCapture.requestAccess { granted in
    guard granted else {
        print("[Permission] Camera access denied. Grant it in System Settings > Privacy & Security > Camera, then re-run.")
        exit(1)
    }

    camera = CameraCapture { pixelBuffer, timestamp in
        let landmarks = tracker.detect(in: pixelBuffer)
        DispatchQueue.main.async {
            gestures.update(landmarks: landmarks, timestamp: timestamp)
            if let snapshot = latestSnapshot {
                debugWindow.present(pixelBuffer: pixelBuffer, snapshot: snapshot)
            }
        }
    }
    camera?.start()
}

signal(SIGINT) { _ in
    print("\n[PalmCtrl] Exiting.")
    exit(0)
}

app.activate(ignoringOtherApps: true)
app.run()
