import AppKit
import SwiftUI
import XCTest

@MainActor
final class ManualPanelHostTests: XCTestCase {
    private final class ResizeModel: ObservableObject {
        @Published var height: CGFloat = 54
    }

    private struct ResizingProbe: View {
        @ObservedObject var model: ResizeModel

        var body: some View {
            HStack(spacing: 0) {
                Color.red.frame(width: model.height, height: model.height)
                Color.blue.frame(width: model.height * 3, height: model.height)
                    .animation(.linear(duration: 1), value: model.height)
            }
            .padding(20)
        }
    }

    private struct SizedProbeView: View {
        let size: CGSize

        var body: some View {
            Color.clear.frame(width: size.width, height: size.height)
        }
    }

    private final class FittingProbeView: NSView {
        var desiredSize = NSSize(width: 240, height: 80)

        override var fittingSize: NSSize { desiredSize }
        override var intrinsicContentSize: NSSize { desiredSize }
    }

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
    }

    func testHostedViewIsIsolatedFromPanelContentView() {
        let panel = makePanel()
        let content = NSView()

        let host = ManualPanelHost(contentView: content, in: panel)

        XCTAssertTrue(host.contentView === content)
        XCTAssertFalse(panel.contentView === content)
        XCTAssertEqual(panel.contentView?.subviews.count, 1)
        XCTAssertTrue(panel.contentView?.subviews.first === content)
    }

    func testHostedViewTracksPanelContentBounds() {
        let panel = makePanel(size: NSSize(width: 320, height: 100))
        let content = NSView()
        _ = ManualPanelHost(contentView: content, in: panel)

        XCTAssertEqual(content.frame, panel.contentView?.bounds)

        panel.setContentSize(NSSize(width: 640, height: 180))

        XCTAssertEqual(content.frame, panel.contentView?.bounds)
        XCTAssertEqual(content.frame.size, NSSize(width: 640, height: 180))
    }

    func testFittingSizeIsDelegatedToHostedView() {
        let panel = makePanel()
        let content = FittingProbeView()
        let host = ManualPanelHost(contentView: content, in: panel)

        XCTAssertEqual(host.fittingSize, NSSize(width: 240, height: 80))

        content.desiredSize = NSSize(width: 420, height: 160)

        XCTAssertEqual(host.fittingSize, NSSize(width: 420, height: 160))
    }

    func testHostedDesiredSizeChangeDoesNotResizePanel() {
        let panel = makePanel(size: NSSize(width: 500, height: 120))
        let content = FittingProbeView()
        _ = ManualPanelHost(contentView: content, in: panel)
        let originalFrame = panel.frame

        content.desiredSize = NSSize(width: 900, height: 400)
        content.invalidateIntrinsicContentSize()
        content.needsLayout = true
        panel.layoutIfNeeded()

        XCTAssertEqual(panel.frame, originalFrame)
    }

    func testHostingViewSizeChangeDoesNotResizeVisiblePanel() {
        let panel = makePanel(size: NSSize(width: 500, height: 120))
        panel.alphaValue = 0
        let content = NSHostingView(rootView: SizedProbeView(size: CGSize(width: 240, height: 80)))
        _ = ManualPanelHost(contentView: content, in: panel)
        panel.orderFront(nil)
        defer { panel.orderOut(nil); panel.close() }
        panel.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        let originalFrame = panel.frame

        content.rootView = SizedProbeView(size: CGSize(width: 900, height: 400))
        content.invalidateIntrinsicContentSize()
        content.needsLayout = true
        panel.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))

        XCTAssertEqual(panel.frame, originalFrame)
    }

    func testZeroSizedPanelStillMeasuresHostingContent() {
        let panel = makePanel(size: .zero)
        let content = NSHostingView(rootView: SizedProbeView(size: CGSize(width: 380, height: 36)))
        let host = ManualPanelHost(contentView: content, in: panel)

        panel.layoutIfNeeded()

        XCTAssertEqual(host.fittingSize, NSSize(width: 380, height: 36))
        XCTAssertEqual(panel.frame.size, .zero)
    }

    func testReplacingPanelContentDetachesHostedViewFromWindow() {
        let panel = makePanel()
        let content = NSView()
        let host = ManualPanelHost(contentView: content, in: panel)
        XCTAssertTrue(content.window === panel)

        panel.contentView = NSView()

        XCTAssertNil(content.window)
        XCTAssertFalse(panel.contentView === content)
        XCTAssertTrue(host.contentView === content)
    }

    func testInteractiveResizeMeasuresPublishedSizeWithoutWaitingForRunLoop() {
        let panel = makePanel(size: NSSize(width: 256, height: 94))
        let model = ResizeModel()
        let presentation = PanelHeightResizePresentation()
        presentation.isActive = true
        let content = NSHostingView(rootView: ResizingProbe(model: model)
            .modifier(PanelHeightResizeModifier(presentation: presentation)))
        let host = ManualPanelHost(contentView: content, in: panel)
        host.layoutContent()

        // Reverse direction repeatedly: neither a stale fitting size nor a label-width
        // animation may put the next panel frame on a different scale from its content.
        for height: CGFloat in [55, 70, 40, 80, 54] {
            model.height = height
            host.layoutContent()
            let expected = NSSize(width: height * 4 + 40, height: height + 40)
            XCTAssertEqual(host.fittingSize, expected)
            panel.setFrame(NSRect(origin: .zero, size: expected), display: false)
            panel.layoutIfNeeded()
            host.layoutContent()
            XCTAssertEqual(content.frame.size, expected)
            XCTAssertEqual(host.fittingSize, expected)
        }
    }

    private func makePanel(size: NSSize = NSSize(width: 400, height: 100)) -> NonConstrainingPanel {
        NonConstrainingPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
    }
}
