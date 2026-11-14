import SwiftUI
import AppKit
import ImageIO

/// Формат записи в строке списка: метка (JSON, SQL…), включено ли форматирование и строка с подсветкой.
struct ClipSyntax {
    /// Длиннее — в строке без подсветки (в окне просмотра — с ней).
    static let rowLimit = 20_000
    let label: String
    let on: Bool
    /// Подсветка готова (считается в фоне); nil — пока текст как есть.
    let text: AttributedString?
}

/// Формат вывода блока команды: метка, включено ли, вывод цветами ANSI и как текст (для копирования).
struct BlockSyntax {
    let label: String
    let on: Bool
    let ansi: String?
    let text: String?
}

/// Буфер обмена (⌘4) на месте истории команд: закреплённые группой наверху, затем недавние,
/// выбранный — фиолетовым. Клик — выбрать, двойной клик — скопировать (как Enter), клик по миниатюре —
/// картинка крупно. У выбранной и под курсором строки — кнопки тех же действий, что и клавиши.
struct ClipboardListView: View {
    let clips: [Clip]
    /// Всего фрагментов (без фильтра): пусто совсем или ничего не нашлось.
    let total: Int
    let query: String
    let selection: Int
    let days: Int
    let lang: String
    var maxHeight: CGFloat = 470
    /// Enter и двойной клик: вставить в приложение (если `pastes`) или скопировать.
    var onCopy: (Clip) -> Void = { _ in }
    /// Enter вставляет сразу: у строки две кнопки — «↩ вставить» и «⌘C копировать».
    var pastes = false
    /// Куда вставит Enter: «вставить в Terminal».
    var pasteTarget: String?
    /// Сколько строк текста видно у записи (настройка «Строк у записи»).
    var rowLines = SettingsStore.defaultClipboardRowLines
    var onCopyOnly: (Clip) -> Void = { _ in }
    var onSelect: (Int) -> Void = { _ in }
    /// ⌘Enter: в поле (у картинки — путь к файлу).
    var onInsert: (Clip) -> Void = { _ in }
    /// ⌘Y и клик по миниатюре: картинка крупно.
    var onPreview: (Clip) -> Void = { _ in }
    var onTogglePin: (Clip) -> Void = { _ in }
    var onDelete: (Clip) -> Void = { _ in }
    /// Файл картинки фрагмента (для миниатюры).
    var imageURL: (Clip) -> URL? = { _ in nil }
    /// Формат текста записи (nil — обычный текст) и {} — форматировать или как есть.
    var syntax: (Clip) -> ClipSyntax? = { _ in nil }
    var onToggleFormat: (Clip) -> Void = { _ in }
    @State private var hovered: UUID?

    private var hasGroups: Bool { clips.contains(where: \.isPinned) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // число и срок — в фильтре над полем, отдельного заголовка нет
            if clips.isEmpty { empty } else { list }
        }
        .sunken(RoundedRectangle(cornerRadius: LauncherMetrics.innerRadius))
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(clips.enumerated()), id: \.element.id) { index, clip in
                        if hasGroups, index == 0 { groupTitle(L.t("clip_pinned", lang), pin: true) }
                        if hasGroups, !clip.isPinned, index == 0 || clips[index - 1].isPinned {
                            groupTitle(L.t("clip_recent", lang), pin: false)
                        }
                        ClipRow(clip: clip, selected: index == selection, showsActions: index == selection || hovered == clip.id,
                                lang: lang, query: query, imageURL: imageURL(clip), syntax: syntax(clip),
                                pastes: pastes, pasteTarget: pasteTarget, rowLines: rowLines,
                                onCopy: { onCopy(clip) }, onCopyOnly: { onCopyOnly(clip) }, onInsert: { onInsert(clip) },
                                onToggleFormat: { onToggleFormat(clip) },
                                onPreview: { onSelect(index); onPreview(clip) },
                                onTogglePin: { onTogglePin(clip) }, onDelete: { onDelete(clip) })
                            .id(clip.id)
                            .contentShape(Rectangle())
                            // двойной клик — скопировать, одиночный — только выбрать
                            .onTapGesture(count: 2) { onCopy(clip) }
                            .onTapGesture { onSelect(index) }
                            .onHover { inside in
                                if inside { hovered = clip.id } else if hovered == clip.id { hovered = nil }
                            }
                        // тонкая граница между записями той же группы; у выбранной своя рамка — рядом с ней не нужна
                        if Self.separates(clips, after: index, selection: selection) {
                            Rectangle()
                                .fill(Color.primary.opacity(0.09))
                                .frame(height: 1)
                                .padding(.leading, 41)
                                .padding(.trailing, 9)
                        }
                    }
                }
                .padding(6)
            }
            .scrollIndicators(.automatic)
            // окно панели берёт высоту по содержимому: у прокрутки она должна быть явной
            .frame(height: min(listHeight, maxHeight))
            .onChange(of: selection) { _, index in
                guard clips.indices.contains(index) else { return }
                proxy.scrollTo(clips[index].id)
            }
        }
    }

    private func groupTitle(_ title: String, pin: Bool) -> some View {
        HStack(spacing: 5) {
            if pin { Image(systemName: "pin.fill").foregroundStyle(Tactile.clip) }
            Text(title.uppercased()).tracking(0.4)
        }
        .font(.system(size: 10.5, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 9)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    /// Граница после строки `index`: следующая есть, в той же группе (закреплённые и недавние разделены
    /// заголовком), и ни одна из двух не выбрана.
    static func separates(_ clips: [Clip], after index: Int, selection: Int) -> Bool {
        guard index + 1 < clips.count else { return false }
        if clips[index].isPinned != clips[index + 1].isPinned { return false }
        return index != selection && index + 1 != selection
    }

    /// Высота строк: однострочная 44, двухстрочная 61, заголовки групп по 22, плюс отступы списка.
    private var listHeight: CGFloat {
        let rows: CGFloat = clips.reduce(12) { total, clip in
            total + (clip.isImage ? 70 : ClipRow.height(lines: shownLines(clip))) + 2
        }
        let titles: CGFloat = hasGroups ? (clips.allSatisfy(\.isPinned) ? 24 : 48) : 0
        // границы между строками: 1 точка и ещё один промежуток списка
        let separators = CGFloat(clips.indices.filter { Self.separates(clips, after: $0, selection: selection) }.count) * 3
        return rows + titles + separators
    }

    /// Первые строки текста записи с оформлением (для тестов — то же, что показывает строка).
    static func rowText(_ text: AttributedString, limit: Int) -> [AttributedString] { ClipRow.lines(text, limit: limit) }
    static func rowHeight(lines: Int) -> CGFloat { ClipRow.height(lines: lines) }

    /// Строк текста у записи: отформатированный — по строкам формата, не больше настройки.
    private func shownLines(_ clip: Clip) -> Int {
        if let syntax = syntax(clip), syntax.on, let text = syntax.text {
            return min(ClipRow.lineCount(String(text.characters)), rowLines)
        }
        return min(clip.lineCount, rowLines)
    }

    private var empty: some View {
        let searching = !query.trimmingCharacters(in: .whitespaces).isEmpty && total > 0
        return Text(searching ? String(format: L.t("clip_none", lang), query) : L.t("clip_empty", lang))
            .font(.system(size: 12.5))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(searching ? .center : .leading)
            .frame(maxWidth: .infinity, alignment: searching ? .center : .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ClipRow: View {
    let clip: Clip
    let selected: Bool
    /// Кнопки «закрепить» и «удалить»: у выбранной строки и под курсором.
    let showsActions: Bool
    let lang: String
    var query = ""
    var imageURL: URL?
    var syntax: ClipSyntax?
    var pastes = false
    var pasteTarget: String?
    var rowLines = SettingsStore.defaultClipboardRowLines
    var onCopy: () -> Void = {}
    var onCopyOnly: () -> Void = {}
    var onInsert: () -> Void = {}
    var onToggleFormat: () -> Void = {}
    var onPreview: () -> Void = {}
    var onTogglePin: () -> Void = {}
    var onDelete: () -> Void = {}

    var body: some View {
        // многострочный текст — кнопки и значок у первой строки, а не посередине высокой записи
        HStack(alignment: !clip.isImage && clip.lineCount > 1 ? .top : .center, spacing: 10) {
            ClipSourceIcon(clip: clip)
            if clip.isImage {
                ClipThumbnail(url: imageURL)
                    .contentShape(Rectangle())
                    .highPriorityGesture(TapGesture().onEnded { onPreview() })
                    .hatchTip(.previewClip, lang)
            }
            VStack(alignment: .leading, spacing: 2) {
                if let image = clip.image {
                    // вместо названия: найденная строка со скриншота, его первая фраза или размер
                    Text(FilterChip.highlighted(imageTitle(image), query))
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else {
                    // текст по строкам, до N строк (настройка); формат включён — отформатированный,
                    // как в окне просмотра. Каждая строка — в одну строку с многоточием: высота известна заранее
                    let source = syntax.flatMap { $0.on ? $0.text : nil } ?? AttributedString(clip.text)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(Self.lines(source, limit: rowLines).enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 12.5, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(height: Self.lineHeight, alignment: .leading)
                        }
                    }
                }
                HStack(spacing: 5) {
                    if let syntax { formatLabel(syntax.label) }
                    if let app = clip.app { Text(app) }
                    if clip.app != nil { Text("·") }
                    Text(Self.relative(clip.copiedAt, lang: lang))
                    if clip.lineCount > 1, !clip.isImage {
                        Text("· " + String(format: L.t("clip_lines", lang), clip.lineCount)).foregroundStyle(.tertiary)
                    }
                    if let image = clip.image, imageTitle(image) != image.summary(lang: lang) {
                        Text("· " + image.summary(lang: lang)).foregroundStyle(.tertiary)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .frame(minWidth: 140, alignment: .leading)
            .layoutPriority(1)
            Spacer(minLength: 8)
            if showsActions {
                // кнопки повторяют клавиши: то же действие мышью. Тесно — одни клавиши, без подписей,
                // чтобы текст записи не сжимался до «С… · 5…»
                ViewThatFits(in: .horizontal) {
                    actionButtons(labeled: true)
                    actionButtons(labeled: false)
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(selected ? Tactile.clip.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Tactile.clip.opacity(0.55) : .clear))
    }

    private func actionButtons(labeled: Bool) -> some View {
        let title = { (text: String) in labeled ? text : nil as String? }
        let pasteTitle = pasteTarget.map { String(format: L.t("clip_paste_into", lang), $0) } ?? L.t("clip_paste", lang)
        return HStack(spacing: 4) {
                    // просмотр — там, где он что-то добавляет: картинка или текст длиннее строки записи
                    if clip.isImage || clip.lineCount > 1 {
                        keyButton(.previewClip, title(L.t("clip_preview", lang)), perform: onPreview)
                    }
                    if let syntax { formatButton(on: syntax.on) }
                    if pastes {
                        keyButton(.pasteInto(pasteTarget), title(pasteTitle), perform: onCopy)
                        keyButton(.copyClipOnly, title(L.t("clip_copy", lang)), perform: onCopyOnly)
                    } else {
                        keyButton(.copyClipToPaste, title(L.t("clip_copy", lang)), perform: onCopy)
                    }
                    keyButton(clip.isImage ? .insertPath : .insertClip,
                              title(L.t(clip.isImage ? "clip_insert_path" : "clip_insert", lang)), perform: onInsert)
                    action(clip.isPinned ? "pin.slash" : "pin", tip: clip.isPinned ? .unpinClip : .pinClip,
                           tint: clip.isPinned ? Tactile.clip : nil, perform: onTogglePin)
                    action("xmark", tip: .deleteClip, tint: nil, perform: onDelete)
        }
        .fixedSize()
    }

    /// Метка формата у строки: JSON, SQL, YAML…
    private func formatLabel(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(Tactile.keyText)
            .padding(.horizontal, 5)
            .frame(height: 15)
            .background(Tactile.keyText.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
    }

    /// {} — форматировать запись или показывать как есть (⇧⌘R).
    private func formatButton(on: Bool) -> some View {
        Button(action: onToggleFormat) {
            Text("{}")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(on ? Tactile.clip : Tactile.keyText)
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(KeyCapButtonStyle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(on ? Tactile.clip.opacity(0.55) : .clear))
        .hatchTip(on ? .formatOff : .formatOn, lang)
    }

    /// Кнопка-колпачок «клавиша + подпись»: то же, что сочетание клавиш.
    /// Клавиша и подпись; без подписи (тесно) — одна клавиша, действие — в подсказке.
    private func keyButton(_ action: HatchAction, _ title: String?, perform: @escaping () -> Void) -> some View {
        let key = action.key ?? ""
        return keyCap(key, title, perform: perform).hatchTip(action, lang)
    }

    private func keyCap(_ key: String, _ title: String?, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack(spacing: 5) {
                KeyHint(key: key)
                if let title {
                    Text(title)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Tactile.keyText)
                        .lineLimit(1)
                }
            }
            .padding(.leading, 4)
            .padding(.trailing, title == nil ? 4 : 8)
            .frame(height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(KeyCapButtonStyle(cornerRadius: 7))
        .fixedSize()
    }

    private func action(_ symbol: String, tip: HatchAction, tint: Color?, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(tint ?? Tactile.keyText)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(KeyCapButtonStyle(cornerRadius: 7))
        .hatchTip(tip, lang)
        .accessibilityLabel(tip.text(lang))
    }

    private func imageTitle(_ image: ClipImage) -> String {
        ClipboardHistory.matchedLine(clip, query) ?? image.firstLine ?? image.summary(lang: lang)
    }

    /// Две первые строки, пробелы в начале строк сохраняются.
    static let lineHeight: CGFloat = 17

    /// Высота строки записи с `lines` строками текста (для высоты списка).
    static func height(lines: Int) -> CGFloat { 46 + CGFloat(max(lines, 1) - 1) * lineHeight }

    static func lineCount(_ text: String) -> Int {
        text.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    /// Первые `limit` строк текста с оформлением.
    static func lines(_ text: AttributedString, limit: Int) -> [AttributedString] {
        var result: [AttributedString] = []
        let chars = text.characters
        var start = chars.startIndex
        var index = chars.startIndex
        while index < chars.endIndex, result.count < limit {
            if chars[index] == "\n" {
                result.append(AttributedString(text[start..<index]))
                start = chars.index(after: index)
            }
            index = chars.index(after: index)
        }
        if result.count < limit, start < chars.endIndex { result.append(AttributedString(text[start..<chars.endIndex])) }
        return result.isEmpty ? [AttributedString("")] : result
    }

    static func relative(_ date: Date, lang: String, now: Date = Date()) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: lang == "ru" ? "ru_RU" : "en_US")
        formatter.unitsStyle = .short
        if now.timeIntervalSince(date) < 60 { return L.t("clip_now", lang) }
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

/// Значок приложения, откуда скопировано; путь — значок папки, неизвестно откуда — листок.
private struct ClipSourceIcon: View {
    let clip: Clip

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                Image(systemName: clip.isPath ? "folder" : "doc.on.clipboard")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 22, height: 22)
    }

    private var image: NSImage? {
        guard let id = clip.bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

/// Миниатюра картинки из буфера: уменьшенная копия (не вся картинка в памяти), с кешем.
struct ClipThumbnail: View {
    let url: URL?
    var width: CGFloat = 96
    var height: CGFloat = 56

    var body: some View {
        Group {
            if let url, let image = ThumbnailCache.shared.image(for: url) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(Color.primary.opacity(0.08))
                    .overlay(Image(systemName: "photo").foregroundStyle(.tertiary))
            }
        }
        // от левого верхнего угла: у скриншота там начало текста (по центру резалась середина строки)
        .frame(width: width, height: height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
    }
}

final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSURL, NSImage>()

    /// Уменьшенная копия до 240 точек по длинной стороне (хватает и для Retina-миниатюры).
    func image(for url: URL) -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 240,
                  kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}
