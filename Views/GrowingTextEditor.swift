import SwiftUI
import AppKit

struct GrowingTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    @Binding var pinnedToMax: Bool

    var maxLines: Int = 10

    /// Extra reserved width INSIDE the text layout area (e.g. paperclip button)
    var leadingAccessoryWidth: CGFloat = 0

    /// Extra reserved width INSIDE the text layout area (e.g. send button)
    var trailingAccessoryWidth: CGFloat = 0

    /// Called when user presses Enter (Return). Shift+Enter inserts a new line.
    var onEnterSend: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = CustomNSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.backgroundColor = .clear
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .labelColor

        // make wrapping predictable
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.textContainer?.lineFragmentPadding = 0

        // insets
        textView.textContainerInset = NSSize(width: 8, height: 8) // базово
        // фактический inset скорректируется в updateContainerWidth()

        // hook up callbacks & accessory widths
        textView.onEnterSend = onEnterSend
        textView.leadingAccessoryWidth = leadingAccessoryWidth
        textView.trailingAccessoryWidth = trailingAccessoryWidth
        textView.needsLayout = true
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)

        // initial text
        textView.string = text

        // delegate for text changes
        textView.delegate = context.coordinator

        scrollView.documentView = textView

        // initial sizing
        context.coordinator.recalculateHeight(for: textView, in: scrollView)

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? CustomNSTextView else { return }

        // keep callback updated (it can capture contact etc.)
        textView.onEnterSend = onEnterSend

        // update accessory widths (affects layout width)
        textView.leadingAccessoryWidth = leadingAccessoryWidth
        textView.trailingAccessoryWidth = trailingAccessoryWidth

        // update text if needed
        if textView.string != text {
            textView.string = text
        }

        // recompute layout + height
        context.coordinator.recalculateHeight(for: textView, in: nsView)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: GrowingTextEditor

        init(parent: GrowingTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView,
                  let scrollView = textView.enclosingScrollView else { return }

            // sync SwiftUI binding
            let newText = textView.string
            if parent.text != newText {
                parent.text = newText
            }

            recalculateHeight(for: textView, in: scrollView)
        }

        func recalculateHeight(for textView: NSTextView, in scrollView: NSScrollView) {
            // Ensure layout is up to date
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            layoutManager.ensureLayout(for: textContainer)

            // Used rect height (content height)
            let used = layoutManager.usedRect(for: textContainer).size.height

            // Insets (top+bottom)
            let insetY = textView.textContainerInset.height * 2

            // Line height (fallback if font nil)
            let lineHeight: CGFloat = (textView.font?.boundingRectForFont.height ?? 17)

            // Minimum height = 1 line + insets
            let minHeight = lineHeight + insetY

            // Maximum height = maxLines + insets
            let maxHeight = (lineHeight * CGFloat(max(parent.maxLines, 1))) + insetY

            // Desired height (clamped)
            let desired = min(max(used + insetY, minHeight), maxHeight)

            let shouldPin = (used + insetY) > maxHeight + 0.5

            // Toggle inner scrolling when pinned
            scrollView.hasVerticalScroller = shouldPin
            scrollView.autohidesScrollers = true

            if parent.pinnedToMax != shouldPin {
                DispatchQueue.main.async {
                    self.parent.pinnedToMax = shouldPin
                }
            }

            // Update height binding only if it meaningfully changed (reduces "jumping")
            if abs(parent.height - desired) > 0.5 {
                DispatchQueue.main.async {
                    self.parent.height = desired
                }
            }
        }
    }
}

// MARK: - CustomNSTextView

final class CustomNSTextView: NSTextView {

    var onEnterSend: (() -> Void)?

    /// Reserved width inside text layout (left)
    var leadingAccessoryWidth: CGFloat = 0 {
        didSet { updateContainerWidth() }
    }

    /// Reserved width inside text layout (right)
    var trailingAccessoryWidth: CGFloat = 0 {
        didSet { updateContainerWidth() }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateContainerWidth()
    }

    private func updateContainerWidth() {
        guard let textContainer = textContainer else { return }

        // Сколько реального "паддинга" мы хотим внутри текста слева/справа
        let basePad: CGFloat = 8

        // Реальный старт текста (курсор) сдвигаем вправо/влево за счёт inset
        textContainerInset = NSSize(
            width: basePad + leadingAccessoryWidth,
            height: textContainerInset.height
        )

        // А справа резерв делаем через уменьшение ширины контейнера
        let rightInset = basePad + trailingAccessoryWidth

        let usable = max(0, bounds.width - (textContainerInset.width + rightInset))

        textContainer.containerSize = NSSize(width: usable, height: .greatestFiniteMagnitude)
        textContainer.widthTracksTextView = false
    }

    override func keyDown(with event: NSEvent) {
        // Return (36) or Numpad Enter (76)
        if event.keyCode == 36 || event.keyCode == 76 {
            // Shift+Enter -> newline
            if event.modifierFlags.contains(.shift) {
                insertNewline(nil)
                return
            }
            // Enter -> send (if handler exists)
            if let onEnterSend = onEnterSend {
                onEnterSend()
                return
            }
        }

        super.keyDown(with: event)
    }
}
