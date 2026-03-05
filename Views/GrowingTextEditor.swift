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
        textView.applyStableTypingAttributes()
        
        
        
        // Fix caret vertical position when text is empty
        let p = NSMutableParagraphStyle()
        p.minimumLineHeight = textView.font?.boundingRectForFont.height ?? 17
        p.maximumLineHeight = p.minimumLineHeight
        p.lineSpacing = 0
        p.paragraphSpacing = 0
        p.paragraphSpacingBefore = 0

        textView.typingAttributes = [
            .font: textView.font as Any,
            .foregroundColor: textView.textColor as Any,
            .paragraphStyle: p
        ]

        // Also apply as default attributes so empty state uses same baseline
        textView.defaultParagraphStyle = p

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
        textView.setPlainString(text)

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
        textView.applyStableTypingAttributes()
        let p = NSMutableParagraphStyle()
        p.minimumLineHeight = textView.font?.boundingRectForFont.height ?? 17
        p.maximumLineHeight = p.minimumLineHeight
        p.lineSpacing = 0
        p.paragraphSpacing = 0
        p.paragraphSpacingBefore = 0

        textView.typingAttributes[.paragraphStyle] = p
        textView.defaultParagraphStyle = p

        // update accessory widths (affects layout width)
        textView.leadingAccessoryWidth = leadingAccessoryWidth
        textView.trailingAccessoryWidth = trailingAccessoryWidth

        // update text if needed
        textView.setPlainString(text)

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

            // 1) Обновляем layout, чтобы usedRect был актуален
            layoutManager.ensureLayout(for: textContainer)

            // 2) Высота контента (без inset-ов)
            let usedHeight = layoutManager.usedRect(for: textContainer).size.height

            // 3) Insets (top + bottom)
            let insetY = textView.textContainerInset.height * 2

            // 4) Line height (fallback)
            let lineHeight: CGFloat = (textView.font?.boundingRectForFont.height ?? 17)

            // 5) Мин/макс высота
            let minHeight = lineHeight + insetY
            let maxHeight = (lineHeight * CGFloat(max(parent.maxLines, 1))) + insetY

            // ✅ ФИКС: небольшой запас сверху, чтобы первая строка не "подрезалась"
            // Это особенно заметно когда включается внутренний скролл.
            let topClipFix: CGFloat = 4

            // 6) Желаемая высота (clamped)
            let desired = min(
                max(usedHeight + insetY + topClipFix, minHeight),
                maxHeight
            )

            // 7) Определяем, достигли ли лимита (нужен ли внутренний скролл)
            // Добавляем небольшой запас, чтобы состояние не "дребезжало" на границе.
            let pinThreshold: CGFloat = 1
            let shouldPin = (usedHeight + insetY + topClipFix) > (maxHeight + pinThreshold)

            // 8) Скролл внутри поля при пине
            scrollView.hasVerticalScroller = shouldPin
            scrollView.autohidesScrollers = true

            if parent.pinnedToMax != shouldPin {
                DispatchQueue.main.async {
                    self.parent.pinnedToMax = shouldPin
                }
            }

            // 9) Обновляем биндинг высоты только при заметном изменении (меньше "прыжков")
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

    // MARK: - Public callbacks / config

    var onEnterSend: (() -> Void)?

    /// Reserved width inside text layout (left)
    var leadingAccessoryWidth: CGFloat = 0 {
        didSet { updateContainerWidth() }
    }

    /// Reserved width inside text layout (right)
    var trailingAccessoryWidth: CGFloat = 0 {
        didSet { updateContainerWidth() }
    }

    // MARK: - Internal state (caret fix)

    private var hasEverEdited = false
    /// Подними/опусти каретку на первом клике в пустом поле (обычно 2–3 идеально)
    private let initialEmptyCaretYFix: CGFloat = -4

    // MARK: - Text helpers

    func setPlainString(_ plain: String) {
        if self.string != plain {
            self.string = plain
        }
        applyStableTypingAttributes()
    }

    func applyStableTypingAttributes() {
        let fontToUse = self.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)

        let p = NSMutableParagraphStyle()
        p.lineSpacing = 0
        p.paragraphSpacing = 0
        p.paragraphSpacingBefore = 0

        let attrs: [NSAttributedString.Key: Any] = [
            .font: fontToUse,
            .foregroundColor: (self.textColor ?? NSColor.labelColor),
            .paragraphStyle: p
        ]

        self.typingAttributes = attrs
        self.defaultParagraphStyle = p

        // Если пусто — всё равно задаём storage с нужными атрибутами (без вставки символов)
        if self.string.isEmpty {
            self.textStorage?.setAttributedString(NSAttributedString(string: "", attributes: attrs))
            self.setSelectedRange(NSRange(location: 0, length: 0))
        }
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok {
            applyStableTypingAttributes()
            updateContainerWidth()
        }
        return ok
    }

    // MARK: - Layout

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateContainerWidth()
    }

    private func updateContainerWidth() {
        guard let textContainer = textContainer else { return }

        let basePad: CGFloat = 8

        // Старт текста/каретки сдвигаем вправо за счёт inset (под скрепку)
        textContainerInset = NSSize(
            width: basePad + leadingAccessoryWidth,
            height: textContainerInset.height
        )

        // Справа резерв делаем через уменьшение ширины контейнера (под самолётик)
        let rightInset = basePad + trailingAccessoryWidth
        let usable = max(0, bounds.width - (textContainerInset.width + rightInset))

        textContainer.containerSize = NSSize(width: usable, height: CGFloat.greatestFiniteMagnitude)
        textContainer.widthTracksTextView = false
    }

    // MARK: - Keys

    override func keyDown(with event: NSEvent) {
        // Return (36) or Numpad Enter (76)
        if event.keyCode == 36 || event.keyCode == 76 {
            // Shift+Enter -> newline
            if event.modifierFlags.contains(.shift) {
                insertNewline(nil)
                return
            }
            // Enter -> send
            if let onEnterSend = onEnterSend {
                onEnterSend()
                return
            }
        }
        super.keyDown(with: event)
    }

    // MARK: - Caret drawing fix (the real fix)

    override func didChangeText() {
        hasEverEdited = true
        super.didChangeText()
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        // rect — это то место, которое AppKit будет стирать/рисовать при мигании.
        // Мы сдвигаем реальный рисунок каретки, но также должны вручную очищать старую область,
        // иначе остаётся "хвостик".

        let needsFix = self.string.isEmpty && !hasEverEdited
        let dy = needsFix ? initialEmptyCaretYFix : 0

        // 1) Стираем "оригинальную" область rect (ту, которую AppKit ожидает)
        // Только когда каретка выключается (blink off), чтобы убрать остатки.
        if !flag {
            self.setNeedsDisplay(rect)
        }

        // 2) Рисуем каретку со сдвигом
        var shifted = rect
        shifted.origin.y += dy
        super.drawInsertionPoint(in: shifted, color: color, turnedOn: flag)

        // 3) И просим перерисовать ещё и сдвинутую область (чтобы не было артефактов)
        self.setNeedsDisplay(shifted)
    }
}

