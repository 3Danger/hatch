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

    func sizeThatFits(_ proposal: ProposedViewSize, nsView scrollView: NSScrollView, context: Context) -> CGSize? {
        guard let textView = scrollView.documentView as? NSTextView,
              let container = textView.textContainer,
              let layoutManager = textView.layoutManager else { return nil }
        let width = proposal.width ?? scrollView.frame.width
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: container)
        let height = ceil(layoutManager.usedRect(for: container).height)
        let findBar = scrollView.isFindBarVisible ? (scrollView.findBarView?.frame.height ?? 0) : 0
        return CGSize(width: width, height: height + findBar)
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
