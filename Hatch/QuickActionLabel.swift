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
            case .suggestApp(let app, _):
                KeyHint(key: "⇥")
                AppIconView(app: app)
                name(app.title).foregroundStyle(.secondary)
            case .openApp(let app):
                KeyHint(key: "↩")
                AppIconView(app: app)
                name(String(format: L.t("quick_open_app", lang), app.title))
            case .openPaths(let app, let urls):
                KeyHint(key: "↩")
                AppIconView(app: app)
                name(String(format: L.t("quick_open_in", lang), pathsTitle(urls), app.title))
            case .calculate(let value):
                Text("= " + Calculator.display(value))
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
        case .suggestApp: L.t("quick_suggest_help", lang)
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
