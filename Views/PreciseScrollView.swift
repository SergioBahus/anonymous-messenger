import SwiftUI
import AppKit

struct PreciseScrollView<Content: View>: NSViewRepresentable {
    @Binding var offsetY: CGFloat
    @Binding var isAtBottom: Bool

    var restoreID: UUID
    var scrollToBottomTick: Int
    let content: Content

    init(
        offsetY: Binding<CGFloat>,
        isAtBottom: Binding<Bool>,
        restoreID: UUID,
        scrollToBottomTick: Int,
        @ViewBuilder content: () -> Content
    ) {
        self._offsetY = offsetY
        self._isAtBottom = isAtBottom
        self.restoreID = restoreID
        self.scrollToBottomTick = scrollToBottomTick
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(offsetY: $offsetY, isAtBottom: $isAtBottom)
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

        if let clipView = scrollView.contentView as NSClipView? {
            clipView.postsBoundsChangedNotifications = true
        }

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

        if context.coordinator.restoreID != restoreID {
            context.coordinator.restoreID = restoreID
            DispatchQueue.main.async {
                context.coordinator.restoreOffset(self.offsetY)
            }
        }

        if context.coordinator.lastScrollToBottomTick != scrollToBottomTick {
            context.coordinator.lastScrollToBottomTick = scrollToBottomTick
            DispatchQueue.main.async {
                context.coordinator.scrollToBottom()
            }
        } else {
            DispatchQueue.main.async {
                context.coordinator.updateBottomState()
            }
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

        weak var scrollView: NSScrollView?
        weak var hostingView: NSHostingView<Content>?

        var restoreID: UUID?
        var lastScrollToBottomTick: Int = 0

        private var didApplyInitialPosition = false
        private var isProgrammaticScroll = false

        init(offsetY: Binding<CGFloat>, isAtBottom: Binding<Bool>) {
            self._offsetY = offsetY
            self._isAtBottom = isAtBottom
        }

        func applyInitialPositionIfNeeded() {
            guard !didApplyInitialPosition else { return }
            didApplyInitialPosition = true
            restoreOffset(offsetY)
        }

        func restoreOffset(_ y: CGFloat) {
            guard let scrollView else { return }
            let maxY = maxScrollableY(in: scrollView)
            let clampedY = max(0, min(y, maxY))

            isProgrammaticScroll = true
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: clampedY))
            scrollView.reflectScrolledClipView(scrollView.contentView)

            DispatchQueue.main.async {
                self.isProgrammaticScroll = false
                self.updateBottomState()
            }
        }

        func scrollToBottom() {
            guard let scrollView else { return }
            let bottomY = maxScrollableY(in: scrollView)

            isProgrammaticScroll = true
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: bottomY))
            scrollView.reflectScrolledClipView(scrollView.contentView)

            offsetY = bottomY
            isAtBottom = true

            DispatchQueue.main.async {
                self.isProgrammaticScroll = false
                self.updateBottomState()
            }
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

            updateBottomState()
        }
    }
}

private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}
