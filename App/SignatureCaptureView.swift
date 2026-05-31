import SwiftUI
import UIKit

/// Full-screen signature capture (spec 9.2: "Подпись на canvas").
/// Presents a finger-drawn canvas backed by a plain UIView + UIBezierPath
/// (no PencilKit dependency). On "Done" it renders the strokes to a flattened
/// UIImage and hands it back through `onComplete`; the caller saves it via
/// ImageStore and attaches it to the Consent as a `.consentSignature` photo.
struct SignatureCaptureView: View {
    /// Called with the rendered signature image when the groomer taps Done.
    let onComplete: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var canvas = SignatureCanvasProxy()
    @State private var hasDrawing = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Sign in the box below")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                SignatureCanvas(proxy: canvas, hasDrawing: $hasDrawing)
                    .frame(maxWidth: .infinity, minHeight: 240)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color(.separator), lineWidth: 1)
                    )
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color(.separator))
                            .frame(height: 1)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 44)
                    }
                    .accessibilityLabel("Signature canvas")

                Text("By signing, the owner accepts the consent terms.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("Signature")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        if let image = canvas.renderImage() {
                            onComplete(image)
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!hasDrawing)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button(role: .destructive) {
                        canvas.clear()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .disabled(!hasDrawing)
                }
            }
        }
    }
}

/// Lightweight handle the SwiftUI layer uses to drive the underlying UIView
/// (clear / render) without owning UIKit state directly.
@MainActor
final class SignatureCanvasProxy {
    fileprivate weak var view: SignatureDrawingView?

    func clear() {
        view?.clear()
    }

    func renderImage() -> UIImage? {
        view?.renderImage()
    }
}

/// Bridges the custom UIKit drawing view into SwiftUI.
private struct SignatureCanvas: UIViewRepresentable {
    let proxy: SignatureCanvasProxy
    @Binding var hasDrawing: Bool

    func makeUIView(context: Context) -> SignatureDrawingView {
        let view = SignatureDrawingView()
        view.onDrawingChanged = { drawn in
            // Bounce back to SwiftUI state; guard against redundant updates.
            if hasDrawing != drawn {
                hasDrawing = drawn
            }
        }
        proxy.view = view
        return view
    }

    func updateUIView(_ uiView: SignatureDrawingView, context: Context) {
        proxy.view = uiView
    }
}

/// Plain UIView that captures finger strokes into UIBezierPaths and renders a
/// flattened image on demand. Touch-driven; no external dependencies.
final class SignatureDrawingView: UIView {
    var onDrawingChanged: ((Bool) -> Void)?

    private var paths: [UIBezierPath] = []
    private var activePath: UIBezierPath?
    private let strokeColor = UIColor.label
    private let strokeWidth: CGFloat = 2.5

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        backgroundColor = .clear
        isMultipleTouchEnabled = false
        isOpaque = false
    }

    var hasDrawing: Bool {
        !paths.isEmpty || activePath != nil
    }

    func clear() {
        paths.removeAll()
        activePath = nil
        setNeedsDisplay()
        onDrawingChanged?(false)
    }

    /// Flattens the current strokes onto an opaque white background so the
    /// signature reads correctly inside a PDF regardless of light/dark mode.
    func renderImage() -> UIImage? {
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        format.scale = UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(bounds)
            UIColor.black.setStroke()
            for path in paths {
                path.stroke()
            }
            activePath?.stroke()
        }
    }

    override func draw(_ rect: CGRect) {
        strokeColor.setStroke()
        for path in paths {
            path.stroke()
        }
        activePath?.stroke()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let path = UIBezierPath()
        path.lineWidth = strokeWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: touch.location(in: self))
        activePath = path
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let path = activePath else { return }
        path.addLine(to: touch.location(in: self))
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finishStroke()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        finishStroke()
    }

    private func finishStroke() {
        if let path = activePath {
            paths.append(path)
            activePath = nil
            setNeedsDisplay()
        }
        onDrawingChanged?(hasDrawing)
    }
}
