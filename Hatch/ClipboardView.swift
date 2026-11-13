import SwiftUI
import AppKit
import ImageIO

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
    var onCopy: (Clip) -> Void = { _ in }
    var onSelect: (Int) -> Void = { _ in }
    /// ⌘Enter: в поле (у картинки — путь к файлу).
    var onInsert: (Clip) -> Void = { _ in }
    /// ⌘1 и клик по миниатюре: картинка крупно.
    var onPreview: (Clip) -> Void = { _ in }
    var onTogglePin: (Clip) -> Void = { _ in }
    var onDelete: (Clip) -> Void = { _ in }
    /// Файл картинки фрагмента (для миниатюры).
    var imageURL: (Clip) -> URL? = { _ in nil }
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
                                lang: lang, query: query, imageURL: imageURL(clip),
                                onCopy: { onCopy(clip) }, onInsert: { onInsert(clip) },
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

    /// Высота строк: однострочная 44, двухстрочная 61, заголовки групп по 22, плюс отступы списка.
    private var listHeight: CGFloat {
        let rows: CGFloat = clips.reduce(12) { $0 + ($1.isImage ? 70 : $1.lineCount > 1 ? 61 : 44) + 2 }
        let titles: CGFloat = hasGroups ? (clips.allSatisfy(\.isPinned) ? 24 : 48) : 0
        return rows + titles
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
    var onCopy: () -> Void = {}
    var onInsert: () -> Void = {}
    var onPreview: () -> Void = {}
    var onTogglePin: () -> Void = {}
    var onDelete: () -> Void = {}

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ClipSourceIcon(clip: clip)
            if clip.isImage {
                ClipThumbnail(url: imageURL)
                    .contentShape(Rectangle())
                    .highPriorityGesture(TapGesture().onEnded { onPreview() })
                    .help(L.t("clip_preview_help", lang))
            }
            VStack(alignment: .leading, spacing: 2) {
                if let image = clip.image {
                    // вместо названия: найденная строка со скриншота, его первая фраза или размер
                    Text(FilterChip.highlighted(imageTitle(image), query))
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else {
                    Text(preview)
                        .font(.system(size: 12.5, design: .monospaced))
                        // однострочный — в одну строку с многоточием: высота списка считается по строкам фрагмента
                        .lineLimit(clip.lineCount > 1 ? 2 : 1)
                        .truncationMode(.tail)
                        .foregroundStyle(.primary)
                }
                HStack(spacing: 5) {
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
            Spacer(minLength: 8)
            if showsActions {
                // кнопки повторяют клавиши: то же действие мышью
                HStack(spacing: 4) {
                    if clip.isImage { keyButton("⌘1", L.t("clip_preview", lang), perform: onPreview) }
                    keyButton("↩", L.t("clip_copy", lang), perform: onCopy)
                    keyButton("⌘↩", L.t(clip.isImage ? "clip_insert_path" : "clip_insert", lang), perform: onInsert)
                    action(clip.isPinned ? "pin.slash" : "pin", help: L.t(clip.isPinned ? "clip_unpin" : "clip_pin", lang) + " (⌘S)",
                           tint: clip.isPinned ? Tactile.clip : nil, perform: onTogglePin)
                    action("xmark", help: L.t("clip_delete", lang) + " (⌘⌫)", tint: nil, perform: onDelete)
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(selected ? Tactile.clip.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Tactile.clip.opacity(0.55) : .clear))
    }

    /// Кнопка-колпачок «клавиша + подпись»: то же, что сочетание клавиш.
    private func keyButton(_ key: String, _ title: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack(spacing: 5) {
                KeyHint(key: key)
                Text(title)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Tactile.keyText)
                    .lineLimit(1)
            }
            .padding(.leading, 4)
            .padding(.trailing, 8)
            .frame(height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(KeyCapButtonStyle(cornerRadius: 7))
        .fixedSize()
    }

    private func action(_ symbol: String, help: String, tint: Color?, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(tint ?? Tactile.keyText)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(KeyCapButtonStyle(cornerRadius: 7))
        .help(help)
    }

    private func imageTitle(_ image: ClipImage) -> String {
        ClipboardHistory.matchedLine(clip, query) ?? image.firstLine ?? image.summary(lang: lang)
    }

    /// Две первые строки, пробелы в начале строк сохраняются.
    private var preview: String {
        clip.text.split(separator: "\n", maxSplits: 2, omittingEmptySubsequences: false).prefix(2).joined(separator: "\n")
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
        .frame(width: width, height: height)
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

/// Картинка из буфера крупно (Space): вписана в 900 × 600, Esc или Space — закрыть.
struct ClipImagePreview: View {
    let url: URL
    let caption: String
    var pinned = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                // ⌘S в просмотре — видно, что закрепилось
                if pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Tactile.clip)
                }
                Text(caption)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 900, maxHeight: 600)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(10)
    }
}
