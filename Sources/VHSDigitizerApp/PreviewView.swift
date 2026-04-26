import AVFoundation
import SwiftUI

struct CapturePreviewView: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView()
        view.previewLayer.session = session
        return view
    }

    func updateNSView(_ nsView: PreviewContainerView, context: Context) {
        nsView.previewLayer.session = session
    }
}

final class PreviewContainerView: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        previewLayer.videoGravity = .resizeAspect
        layer?.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
    }
}
