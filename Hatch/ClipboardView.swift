import SwiftUI
import AppKit

/// Буфер обмена (⌘4) на месте истории команд: закреплённые группой наверху, затем недавние,
/// выбранный — фиолетовым. Клик — скопировать (как Enter). У выбранной и под курсором строки —
/// кнопки «закрепить» и «удалить».
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
    var onTogglePin: (Clip) -> Void = { _ in }
    var onDelete: (Clip) -> Void = { _ in }
    @State private var hovered: UUID?

    private var hasGroups: Bool { clips.contains(where: \.isPinned) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if clips.isEmpty {
                empty
            } else {
                header
                list
            }
        }
        .sunken(RoundedRectangle(cornerRadius: LauncherMetrics.innerRadius))
    }

    private var header: some View {
        HStack {
            Text(query.trimmingCharacters(in: .whitespaces).isEmpty
                 ? String(format: L.t("clip_count", lang), clips.count)
                 : String(format: L.t("clip_found", lang), clips.count))
            Spacer()
            Text(String(format: L.t("clip_days", lang), days))
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 2)
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
                                lang: lang, onTogglePin: { onTogglePin(clip) }, onDelete: { onDelete(clip) })
                            .id(clip.id)
                            .contentShape(Rectangle())
                            .onTapGesture { onCopy(clip) }
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
        let rows: CGFloat = clips.reduce(12) { $0 + ($1.lineCount > 1 ? 61 : 44) + 2 }
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
    var onTogglePin: () -> Void = {}
    var onDelete: () -> Void = {}

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ClipSourceIcon(clip: clip)
            VStack(alignment: .leading, spacing: 2) {
                Text(preview)
                    .font(.system(size: 12.5, design: .monospaced))
                    // однострочный — в одну строку с многоточием: высота списка считается по строкам фрагмента
                    .lineLimit(clip.lineCount > 1 ? 2 : 1)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary)
                HStack(spacing: 5) {
                    if let app = clip.app { Text(app) }
                    if clip.app != nil { Text("·") }
                    Text(Self.relative(clip.copiedAt, lang: lang))
                    if clip.lineCount > 1 {
                        Text("· " + String(format: L.t("clip_lines", lang), clip.lineCount)).foregroundStyle(.tertiary)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            if selected {
                HStack(spacing: 5) {
                    KeyHint(key: "↩")
                    Text(L.t("clip_copy", lang))
                    KeyHint(key: "⌘↩")
                    Text(L.t("clip_insert", lang))
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize()
            }
            if showsActions {
                HStack(spacing: 4) {
                    action(clip.isPinned ? "pin.slash" : "pin", help: L.t(clip.isPinned ? "clip_unpin" : "clip_pin", lang),
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
