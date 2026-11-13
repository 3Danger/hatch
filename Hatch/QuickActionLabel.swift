import SwiftUI
import AppKit

/// Подпись справа в поле ввода: что сделает Enter вместо команды. «⇥ Safari» — подсказка
/// по началу имени, «↩ Открыть Safari», «↩ ~/git/hatch в VS Code», «= 350 ↩ копировать».
struct QuickActionLabel: View {
    let action: QuickAction
    let lang: String

    var body: some View {
        HStack(spacing: 6) {
            switch action {
            case .suggestApp(let suggestion):
                KeyHint(key: suggestion.completesOnEnter ? "↩" : "⇥")
                AppIconView(app: suggestion.app)
                if suggestion.completesOnEnter {
                    name(String(format: L.t("quick_complete", lang), suggestion.name)).foregroundStyle(.secondary)
                } else if suggestion.others > 0 {
                    name(String(format: L.t("quick_more", lang), suggestion.name, suggestion.others)).foregroundStyle(.secondary)
                } else {
                    name(suggestion.name).foregroundStyle(.secondary)
                }
            case .openApp(let app):
                KeyHint(key: "↩")
                AppIconView(app: app)
                name(String(format: L.t("quick_open_app", lang), app.title))
            case .openPaths(let app, let urls):
                KeyHint(key: "↩")
                AppIconView(app: app)
                name(String(format: L.t("quick_open_in", lang), pathsTitle(urls), app.title))
            case .calculate(let value, let separator):
                Text("= " + Calculator.display(value, separator: separator))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Tactile.okText)
                    .fixedSize()
                KeyHint(key: "↩")
                name(L.t("quick_copy", lang)).foregroundStyle(.secondary)
            case .divisionByZero:
                name(L.t("quick_div_zero", lang)).foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 8)
        .frame(height: 26)
        .background { background }
        .transition(.opacity)
        .help(help)
    }

    private func name(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: 300, alignment: .leading)
            .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder private var background: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .circular)
        switch action {
        case .openApp, .openPaths:
            shape.fill(Tactile.accent.opacity(0.16)).overlay(shape.strokeBorder(Tactile.accent.opacity(0.5), lineWidth: 0.5))
        case .calculate:
            shape.fill(Color.primary.opacity(0.06)).overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
        case .suggestApp, .divisionByZero:
            EmptyView()
        }
    }

    private var help: String {
        switch action {
        case .suggestApp(let suggestion):
            L.t(suggestion.completesOnEnter ? "quick_complete_help" : "quick_suggest_help", lang)
        case .openApp, .openPaths: L.t("quick_open_help", lang)
        case .calculate: L.t("quick_copy_help", lang)
        case .divisionByZero: ""
        }
    }

    private func pathsTitle(_ urls: [URL]) -> String {
        guard urls.count == 1, let url = urls.first else { return String(format: L.t("quick_paths", lang), urls.count) }
        return ShellCompletionEngine.normalizeHomePath(url.path)
    }
}

/// Значок приложения 16×16, как в Finder.
struct AppIconView: View {
    let app: AppEntry
    var size: CGFloat = 16

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

/// Подсказка после «Команды нет»: «⇥ git status» — Tab заменит первое слово.
struct FixLabel: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            KeyHint(key: "⇥")
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 300, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.leading, 4)
        .padding(.trailing, 8)
        .frame(height: 26)
    }
}

/// Строка под полем: «✕ Команды gti нет. Похоже: git». Клик по варианту — подставить его.
struct MissingCommandRow: View {
    let missing: MissingCommand
    let suggestions: [String]
    let lang: String
    var onPick: (String) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 6) {
            Text("✕").font(.system(size: 12, weight: .bold)).foregroundStyle(Tactile.redText)
            Text(String(format: L.t("missing_command", lang), missing.word))
                .font(.system(size: 12.5))
                .lineLimit(1)
                .truncationMode(.middle)
            if !suggestions.isEmpty {
                Text(L.t("missing_similar", lang)).font(.system(size: 12.5)).foregroundStyle(.secondary).fixedSize()
                ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                    Button { onPick(suggestion) } label: {
                        HStack(spacing: 4) {
                            if index == 0 { KeyHint(key: "⇥") }
                            // вся исправленная команда: видно, что именно выполнится
                            Text(index == 0 ? CommandNotFound.replacingFirstWord(in: missing.command, with: suggestion) : suggestion)
                                .font(.system(size: 12, design: .monospaced))
                                .lineLimit(1)
                        }
                        .padding(.leading, index == 0 ? 3 : 7)
                        .padding(.trailing, 7)
                        .frame(height: 22)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Tactile.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Tactile.red.opacity(0.35), lineWidth: 0.5))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
