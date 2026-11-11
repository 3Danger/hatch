import SwiftUI

/// Экран настроек (тема, язык, лимит, шелл, тайм-аут).
struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    private var lang: String { settings.languageCode }

    var body: some View {
        Form {
            HStack {
                Text(L.t("hotkey", lang))
                Spacer()
                HotKeyField(spec: hotkeyBinding, lang: lang)
            }

            Picker(L.t("theme", lang), selection: themeBinding) {
                ForEach(ThemePreference.allCases, id: \.rawValue) { theme in
                    Text(theme.rawValue.capitalized).tag(theme.rawValue)
                }
            }

            Picker(L.t("language", lang), selection: languageBinding) {
                Text("English").tag("en")
                Text("Русский").tag("ru")
            }

            Stepper(value: historyLimitBinding, in: 1...500) {
                Text("\(L.t("history_limit", lang)): \(settings.historyLimit)")
            }

            TextField(L.t("shell", lang), text: shellBinding)

            TextField(L.t("timeout", lang), value: timeoutBinding, format: .number)

            Toggle(L.t("latin_layout", lang), isOn: latinLayoutBinding)
                .help(L.t("latin_layout_hint", lang))

            HStack {
                Spacer()
                Button("OK") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            HStack {
                Spacer()
                Text("Hatch \(version)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .padding(8)
    }

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "v\(v) (\(b))"
    }

    private var hotkeyBinding: Binding<String> {
        Binding(get: { settings.hotkeyString }, set: { settings.hotkeyString = $0 })
    }
    private var themeBinding: Binding<String> {
        Binding(get: { settings.themeRaw }, set: { settings.themeRaw = $0 })
    }
    private var languageBinding: Binding<String> {
        Binding(get: { settings.languageCode }, set: { settings.languageCode = $0 })
    }
    private var historyLimitBinding: Binding<Int> {
        Binding(get: { settings.historyLimit }, set: { settings.historyLimit = $0 })
    }
    private var shellBinding: Binding<String> {
        Binding(get: { settings.shellPath }, set: { settings.shellPath = $0 })
    }
    private var latinLayoutBinding: Binding<Bool> {
        Binding(get: { settings.latinLayoutInInput }, set: { settings.latinLayoutInInput = $0 })
    }
    private var timeoutBinding: Binding<TimeInterval> {
        Binding(get: { settings.timeoutSeconds }, set: { settings.timeoutSeconds = $0 })
    }
}
