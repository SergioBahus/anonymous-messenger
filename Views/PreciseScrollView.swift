import SwiftUI
import AppKit

struct PreciseScrollView<Content: View>: NSViewRepresentable {
    @Binding var offsetY: CGFloat
    @Binding var isAtBottom: Bool
    @Binding var contentHeight: CGFloat
    @Binding var viewportHeight: CGFloat

    var restoreID: UUID
    var scrollToBottomTick: Int
    var scrollToOffsetTick: Int
    var targetOffsetY: CGFloat

    let content: Content

    init(
        offsetY: Binding<CGFloat>,
        isAtBottom: Binding<Bool>,
        contentHeight: Binding<CGFloat>,
        viewportHeight: Binding<CGFloat>,
        restoreID: UUID,
        scrollToBottomTick: Int,
        scrollToOffsetTick: Int,
        targetOffsetY: CGFloat,
        @ViewBuilder content: () -> Content
    ) {
        self._offsetY = offsetY
        self._isAtBottom = isAtBottom
        self._contentHeight = contentHeight
        self._viewportHeight = viewportHeight
        self.restoreID = restoreID
        self.scrollToBottomTick = scrollToBottomTick
        self.scrollToOffsetTick = scrollToOffsetTick
        self.targetOffsetY = targetOffsetY
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            offsetY: $offsetY,
            isAtBottom: $isAtBottom,
            contentHeight: $contentHeight,
            viewportHeight: $viewportHeight
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let documentView = FlippedDocumentView()
        documentView.translatesAutoresizingMaskIntoConstraints = false

        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        documentView.addSubview(hostingView)
        scrollView.documentView = documentView

        scrollView.contentView.postsBoundsChangedNotifications = true

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: documentView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),

            hostingView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])

        context.coordinator.scrollView = scrollView
        context.coordinator.hostingView = hostingView
        context.coordinator.restoreID = restoreID
        context.coordinator.lastScrollToBottomTick = scrollToBottomTick
        context.coordinator.lastScrollToOffsetTick = scrollToOffsetTick

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.boundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        DispatchQueue.main.async {
            context.coordinator.applyInitialPositionIfNeeded()
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.hostingView?.rootView = content
        context.coordinator.updateMetrics()

        if context.coordinator.restoreID != restoreID {
            context.coordinator.restoreID = restoreID
            DispatchQueue.main.async {
                context.coordinator.restoreOffset(self.offsetY)
            }
            return
        }

        if context.coordinator.lastScrollToOffsetTick != scrollToOffsetTick {
            context.coordinator.lastScrollToOffsetTick = scrollToOffsetTick
            let target = targetOffsetY
            DispatchQueue.main.async {
                context.coordinator.restoreOffset(target)
            }
            return
        }

        if context.coordinator.lastScrollToBottomTick != scrollToBottomTick {
            context.coordinator.lastScrollToBottomTick = scrollToBottomTick
            DispatchQueue.main.async {
                context.coordinator.scrollToBottom()
            }
            return
        }

        DispatchQueue.main.async {
            context.coordinator.updateMetrics()
            context.coordinator.updateBottomState()
        }
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(
            coordinator,
            name: NSView.boundsDidChangeNotification,
            object: nsView.contentView
        )
    }

    final class Coordinator: NSObject {
        @Binding var offsetY: CGFloat
        @Binding var isAtBottom: Bool
        @Binding var contentHeight: CGFloat
        @Binding var viewportHeight: CGFloat

        weak var scrollView: NSScrollView?
        weak var hostingView: NSHostingView<Content>?

        var restoreID: UUID?
        var lastScrollToBottomTick: Int = 0
        var lastScrollToOffsetTick: Int = 0

        private var didApplyInitialPosition = false
        private var isProgrammaticScroll = false

        init(
            offsetY: Binding<CGFloat>,
            isAtBottom: Binding<Bool>,
            contentHeight: Binding<CGFloat>,
            viewportHeight: Binding<CGFloat>
        ) {
            self._offsetY = offsetY
            self._isAtBottom = isAtBottom
            self._contentHeight = contentHeight
            self._viewportHeight = viewportHeight
        }

        func applyInitialPositionIfNeeded() {
            guard !didApplyInitialPosition else { return }
            didApplyInitialPosition = true
            updateMetrics()
            restoreOffset(offsetY)
        }

        func restoreOffset(_ y: CGFloat) {
            guard let scrollView else { return }

            updateMetrics()

            let maxY = maxScrollableY(in: scrollView)
            let clampedY = max(0, min(y, maxY))

            isProgrammaticScroll = true
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: clampedY))
            scrollView.reflectScrolledClipView(scrollView.contentView)

            offsetY = clampedY

            DispatchQueue.main.async {
                self.isProgrammaticScroll = false
                self.updateMetrics()
                self.updateBottomState()
            }
        }

        func scrollToBottom() {
            guard let scrollView else { return }

            updateMetrics()

            let bottomY = maxScrollableY(in: scrollView)

            isProgrammaticScroll = true
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: bottomY))
            scrollView.reflectScrolledClipView(scrollView.contentView)

            offsetY = bottomY
            isAtBottom = true

            DispatchQueue.main.async {
                self.isProgrammaticScroll = false
                self.updateMetrics()
                self.updateBottomState()
            }
        }

        func updateMetrics() {
            guard let scrollView else { return }

            let clipHeight = scrollView.contentView.bounds.height
            let docHeight = scrollView.documentView?.bounds.height ?? 0

            viewportHeight = clipHeight
            contentHeight = docHeight
        }

        func updateBottomState() {
            guard let scrollView else { return }

            let clipHeight = scrollView.contentView.bounds.height
            let docHeight = scrollView.documentView?.bounds.height ?? 0
            let currentY = scrollView.contentView.bounds.origin.y

            let threshold: CGFloat = 24
            let atBottomNow = currentY + clipHeight >= docHeight - threshold
            isAtBottom = atBottomNow
        }

        func maxScrollableY(in scrollView: NSScrollView) -> CGFloat {
            let clipHeight = scrollView.contentView.bounds.height
            let docHeight = scrollView.documentView?.bounds.height ?? 0
            return max(0, docHeight - clipHeight)
        }

        @objc func boundsDidChange(_ notification: Notification) {
            guard let scrollView else { return }

            let currentY = scrollView.contentView.bounds.origin.y

            if !isProgrammaticScroll {
                offsetY = currentY
            }

            updateMetrics()
            updateBottomState()
        }
    }
}

private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}
