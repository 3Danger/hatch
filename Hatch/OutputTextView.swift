import SwiftUI
import AppKit

/// Раскрытый вывод завершённой команды в нативном текстовом поле:
/// сотни тысяч строк без тормозов, выделение, поиск ⌘F. Высота — точно по тексту,
/// поэтому блок растёт по содержимому, а прокручивается список вокруг него.
/// Выглядит как остальной вывод: тот же моноширинный шрифт, цвета, прозрачный фон.
struct OutputTextView: NSViewRepresentable {
    let text: NSAttributedString

    final class Coordinator {
        /// Последний показанный текст: тот же объект (из кеша) — ничего не делаем.
        var shown: NSAttributedString?
        let measurer = TextHeightMeasurer()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = OutputNSTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.allowsUndo = false
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true

        // панель поиска ⌘F появляется в окружающем NSScrollView; сам он не прокручивает —
        // его высота равна высоте текста
        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .none
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard context.coordinator.shown !== text,
              let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.shown = text
        textView.textStorage?.setAttributedString(text)
    }

    /// Высота считается отдельно от показанного поля и ничего в нём не меняет: правка живого
    /// поля посреди раскладки SwiftUI заново запрашивала раскладку окна, а до первой подстановки
    /// текста давала высоту 0 — высота списка прыгала, и AppKit обрывал приложение.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView scrollView: NSScrollView, context: Context) -> CGSize? {
        let width = proposal.width ?? scrollView.frame.width
        guard width > 0 else { return nil }
        let height = context.coordinator.measurer.height(of: text, width: width)
        let findBar = scrollView.isFindBarVisible ? (scrollView.findBarView?.frame.height ?? 0) : 0
        return CGSize(width: width, height: height + findBar)
    }
}

/// Высота текста при заданной ширине — на собственном наборе NSTextStorage/NSLayoutManager,
/// с запоминанием последнего результата: SwiftUI спрашивает размер много раз подряд.
final class TextHeightMeasurer {
    private let storage = NSTextStorage()
    private let layoutManager = NSLayoutManager()
    private let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
    private var measured: NSAttributedString?
    private var cache: [CGFloat: CGFloat] = [:]

    init() {
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
    }

    func height(of text: NSAttributedString, width: CGFloat) -> CGFloat {
        if measured !== text {
            measured = text
            cache = [:]
            storage.setAttributedString(text)
        }
        if let cached = cache[width] { return cached }
        container.size = NSSize(width: width, height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: container)
        let height = ceil(layoutManager.usedRect(for: container).height)
        cache[width] = height
        return height
    }
}

/// ⌘F без главного меню (у приложения его нет): открывает поиск по выводу.
final class OutputNSTextView: NSTextView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command, event.keyCode == 3 { // F — по коду клавиши, в любой раскладке
            let action = NSMenuItem()
            action.tag = NSTextFinder.Action.showFindInterface.rawValue
            performTextFinderAction(action)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
