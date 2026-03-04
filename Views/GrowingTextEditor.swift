import SwiftUI
import AppKit

struct GrowingTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    @Binding var pinnedToMax: Bool

    var maxLines: Int = 10

    /// Enter -> Send
    var onEnterSend: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, height: $height, pinnedToMax: $pinnedToMax, maxLines: maxLines)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true

        let textView = CustomNSTextView()
        textView.delegate = context.coordinator

        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true

        // перенос строк
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineBreakMode = .byWordWrapping

        // фон рисуем SwiftUI-обёрткой
        textView.drawsBackground = false
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.textContainerInset = NSSize(width: 8, height: 8)

        // Enter/Shift+Enter логика
        textView.onEnterSend = onEnterSend

        textView.string = text
        scrollView.documentView = textView

        DispatchQueue.main.async {
            context.coordinator.recalculateHeight(textView: textView, scrollView: scrollView)
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? CustomNSTextView else { return }

        if textView.string != text {
            textView.string = text
        }
        textView.onEnterSend = onEnterSend

        context.coordinator.recalculateHeight(textView: textView, scrollView: nsView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        @Binding var height: CGFloat
        @Binding var pinnedToMax: Bool
        let maxLines: Int

        init(text: Binding<String>, height: Binding<CGFloat>, pinnedToMax: Binding<Bool>, maxLines: Int) {
            _text = text
            _height = height
            _pinnedToMax = pinnedToMax
            self.maxLines = maxLines
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView,
                  let scroll = tv.enclosingScrollView else { return }

            text = tv.string

            // если текст пустой — снимаем “залипание” (после отправки/очистки)
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                pinnedToMax = false
            }

            recalculateHeight(textView: tv, scrollView: scroll)
        }

        func recalculateHeight(textView: NSTextView, scrollView: NSScrollView) {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            let availableWidth = max(50, scrollView.contentSize.width)
            textContainer.containerSize = NSSize(width: availableWidth, height: .greatestFiniteMagnitude)
            textContainer.widthTracksTextView = true

            layoutManager.ensureLayout(for: textContainer)

            let used = layoutManager.usedRect(for: textContainer).height
            let inset = textView.textContainerInset.height
            let contentHeight = used + inset * 2

            let lineHeight: CGFloat = {
                if let font = textView.font {
                    return font.ascender - font.descender + font.leading
                }
                return 18
            }()

            let minHeight = (lineHeight * 1) + inset * 2
            let maxHeight = (lineHeight * CGFloat(maxLines)) + inset * 2

            // если дошли до максимума — “залипаем”
            if contentHeight >= maxHeight - 0.5, !pinnedToMax {
                pinnedToMax = true
            }

            // высота:
            // - если залипли и текст не пустой -> держим maxHeight
            // - иначе растём/уменьшаемся обычно
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let targetHeight: CGFloat
            if pinnedToMax, !trimmed.isEmpty {
                targetHeight = maxHeight
            } else {
                targetHeight = min(maxHeight, max(minHeight, contentHeight))
            }

            // скролл внутри поля включаем только когда контента больше maxHeight
            let needsScroll = contentHeight > maxHeight + 0.5
            scrollView.hasVerticalScroller = needsScroll

            if abs(height - targetHeight) > 0.5 {
                DispatchQueue.main.async {
                    self.height = targetHeight
                }
            }

            // Для скролла документ должен быть выше видимой области
            if let doc = scrollView.documentView {
                var f = doc.frame
                f.size.width = availableWidth
                f.size.height = max(contentHeight, targetHeight)
                doc.frame = f
            }
        }
    }
}

final class CustomNSTextView: NSTextView {
    var onEnterSend: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        // Enter
        if event.keyCode == 36 {
            // Shift+Enter -> новая строка
            if event.modifierFlags.contains(.shift) {
                super.keyDown(with: event)
                return
            }
            // Enter -> отправка
            onEnterSend?()
            return
        }
        super.keyDown(with: event)
    }
}
