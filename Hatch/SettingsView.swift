import SwiftUI
import AppKit

/// Настройки — слой поверх панели (панель за ним отходит назад и темнеет). Без прозрачности:
/// сплошные группы, лунки для полей, колпачки для кнопок.
/// Горячая клавиша колпачками с записью, тема и язык сегментами, глубина истории счётчиком.
struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(ClipboardHistory.self) private var clipboard
    var onClose: () -> Void = {}
    @State private var aliasDraft = ""
    @State private var exclusionDraft = ""
    /// Высота групп: на невысоком экране они прокручиваются, кнопки внизу всегда видны.
    @State private var groupsHeight: CGFloat = 0
    /// Сочетание снимка занято самой macOS (проверяется, пока открыты настройки: его выключают там).
    @State private var screenshotTaken = false
    @State private var screenRecordingAllowed = CGPreflightScreenCaptureAccess()

    private var lang: String { settings.languageCode }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L.t("settings", lang)).font(.system(size: 17, weight: .semibold))
                Spacer()
                Button(action: onClose) {
                    // как в макете: круглый колпачок 28 со знаком «✕» и тенью в 1 точку
                    Text("✕")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Circle())
                }
                .buttonStyle(KeyCapButtonStyle(cornerRadius: 14, under: 1))
                .help(L.t("close", lang))
                .accessibilityLabel(L.t("close", lang))
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)

            ScrollView {
            VStack(spacing: 0) {
            group {
                row(L.t("hotkey", lang), first: true) { HotKeyCapsField(spec: binding(\.hotkeyString), lang: lang) }
                row(L.t("folder_tree", lang), hint: L.t("folder_tree_hint", lang)) {
                    HotKeyCapsField(spec: binding(\.folderTreeShortcut), lang: lang)
                }
                row(L.t("status_icon", lang), hint: L.t("status_icon_hint", lang)) {
                    Toggle("", isOn: binding(\.showStatusIcon))
                        .toggleStyle(GlassSwitchStyle())
                        .labelsHidden()
                }
                row(L.t("theme", lang)) {
                    GlassSegmented(options: ThemePreference.allCases.map { ($0.rawValue, L.t("theme_\($0.rawValue)", lang)) },
                                   selection: binding(\.themeRaw))
                }
                row(L.t("language", lang)) {
                    GlassSegmented(options: [("ru", "Русский"), ("en", "English")], selection: binding(\.languageCode))
                }
            }

            group {
                row(L.t("history_limit", lang), first: true) { GlassStepper(value: binding(\.historyLimit), range: 10...500, step: 10) }
                row(L.t("preview_lines", lang)) {
                    GlassStepper(value: binding(\.previewLines), range: SettingsStore.previewLinesRange)
                }
                row(L.t("shell", lang)) {
                    GlassField(text: binding(\.shellPath), width: 160)
                }
                row(L.t("timeout", lang)) {
                    GlassField(text: Binding(
                        get: { settings.timeoutSeconds == 0 ? "" : String(Int(settings.timeoutSeconds)) },
                        set: { settings.timeoutSeconds = TimeInterval(Int($0.filter(\.isNumber)) ?? 0) }),
                               placeholder: L.t("timeout_none", lang), width: 80)
                }
                row(L.t("latin_layout", lang)) {
                    Toggle("", isOn: binding(\.latinLayoutInInput))
                        .toggleStyle(GlassSwitchStyle())
                        .labelsHidden()
                        .help(L.t("latin_layout_hint", lang))
                }
            }

            group { appRows }
            group { clipboardRows }
            group { screenshotRows }
                .task(id: "\(settings.screenshotsEnabled) \(settings.screenshotShortcut)") {
                    while !Task.isCancelled {
                        screenshotTaken = settings.screenshotsEnabled && SystemScreenshotShortcuts.isTaken(settings.screenshotShortcut)
                        screenRecordingAllowed = CGPreflightScreenCaptureAccess()
                        try? await Task.sleep(for: .seconds(2))
                    }
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { groupsHeight = $0 }
            }
            .scrollIndicators(.automatic)
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(groupsHeight, Self.maxGroupsHeight))

            HStack(spacing: 8) {
                Text("Hatch \(version)").font(.caption).foregroundStyle(.tertiary)
                Spacer()
                // выход без значка в строке меню (и ⌘Q в панели)
                Button { NSApp.terminate(nil) } label: {
                    Text(L.t("quit", lang))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Tactile.redText)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                }
                .buttonStyle(KeyCapButtonStyle(cornerRadius: 10))
                Button(action: onClose) {
                    Text(L.t("done", lang))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(height: 34)
                }
                .buttonStyle(KeyCapButtonStyle(cornerRadius: 10, primary: true))
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 14)
        }
        .frame(width: 440)
        // тени — только у подложки карточки, не у текста внутри
        .background {
            RoundedRectangle(cornerRadius: 22).fill(Tactile.surface)
                .shadow(color: .black.opacity(0.4), radius: 0, y: 2)
                .shadow(color: .black.opacity(0.6), radius: 30, y: 18)
        }
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Tactile.surfaceEdge))
        .overlay(RoundedRectangle(cornerRadius: 22).inset(by: 1)
            .stroke(LinearGradient(colors: [.white.opacity(0.08), .clear], startPoint: .top, endPoint: .center), lineWidth: 1))
    }

    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(Tactile.group, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Tactile.groupEdge))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
    }

    private func row<Control: View>(_ title: String, hint: String? = nil, first: Bool = false,
                                    @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14))
                if let hint {
                    Text(hint)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            control()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, hint == nil ? 0 : 9)
        .frame(minHeight: 46)
        .overlay(alignment: .top) { if !first { Rectangle().fill(Tactile.groupEdge).frame(height: 1) } }
    }

    private func binding<T>(_ keyPath: ReferenceWritableKeyPath<SettingsStore, T>) -> Binding<T> {
        Binding(get: { settings[keyPath: keyPath] }, set: { settings[keyPath: keyPath] = $0 })
    }

    /// Сколько места под группы: экран минус заголовок, кнопки и отступы панели.
    private static var maxGroupsHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 900) - 220
    }

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "v\(v) (\(b))"
    }
}

// MARK: - Элементы настроек

/// Сегменты с бегунком, который упруго переезжает к выбранному.
struct GlassSegmented: View {
    let options: [(id: String, title: String)]
    @Binding var selection: String
    /// Приглушённая подпись после названия (число фрагментов в фильтре буфера).
    var details: [String: String] = [:]
    /// Мельче — для строки над полем ввода (фильтр буфера), той же высоты, что путь.
    var compact = false
    /// Рамки сегментов в координатах самой полоски — по ним стоит бегунок.
    @State private var frames: [String: CGRect] = [:]
    /// Где стоит бегунок. Анимируется отдельно от выбора — см. `.onChange(of: selection)`.
    @State private var thumb: CGRect?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.id) { option in
                let selected = option.id == selection
                // без withAnimation: анимируется только бегунок, а не всё, что зависит от выбора
                // (в буфере — список и высота панели); Tab в буфере выбирает так же
                Button { selection = option.id } label: {
                    // как в макете: шрифт 13 без жирности, выбранный — белый, бегунок — колпачок
                    HStack(spacing: 4) {
                        Text(option.title)
                            .foregroundStyle(selected ? Tactile.keyTextHover : .secondary)
                        if let detail = details[option.id] {
                            Text(detail).foregroundStyle(.tertiary).monospacedDigit()
                        }
                    }
                    .font(.system(size: compact ? 11.5 : 13))
                    .padding(.horizontal, compact ? 8 : 11)
                    .frame(height: compact ? 18 : 26)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: {
                        frames[option.id] = $0
                        if option.id == selection { thumb = $0 } // ширина сегмента поменялась (число)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .coordinateSpace(.named(Self.space))
        // Один бегунок позади всех подписей: у фона кнопки он, переезжая, ложился поверх соседних.
        .background(alignment: .topLeading) {
            if let thumb {
                Color.clear
                    .tactileRaised(RoundedRectangle(cornerRadius: compact ? 5 : 7, style: .circular))
                    .frame(width: thumb.width, height: thumb.height)
                    .offset(x: thumb.minX, y: thumb.minY)
            }
        }
        // Анимируется только место бегунка в полоске, своей транзакцией. Если анимировать всё, что
        // меняет выбор, вместе с ним анимируется и сдвиг самой полоски (в буфере от типа зависит
        // высота панели), и бегунок едет по диагонали.
        .onChange(of: selection) { _, new in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { thumb = frames[new] }
        }
        .padding(compact ? 2 : 3)
        .tactileWell(RoundedRectangle(cornerRadius: compact ? 7 : 10))
    }

    private static let space = "GlassSegmented"
}

/// Счётчик: − значение +, цифра прокручивается при смене.
struct GlassStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1

    var body: some View {
        HStack(spacing: 2) {
            stepButton("minus", delta: -step)
            Text("\(value)")
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(value)))
                .frame(width: 52)
            stepButton("plus", delta: step)
        }
        .padding(3)
        .tactileWell(RoundedRectangle(cornerRadius: 10))
    }

    private func stepButton(_ symbol: String, delta: Int) -> some View {
        StepButton(symbol: symbol) {
            let next = min(max(value + delta, range.lowerBound), range.upperBound)
            withAnimation(.snappy) { value = next }
        }
    }
}

/// Кнопка счётчика как в макете: тонкий знак «−»/«+» в лунке, подсветка при наведении, проседает при нажатии.
private struct StepButton: View {
    let symbol: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(symbol == "minus" ? "−" : "+")
                .font(.system(size: 16))
                .foregroundStyle(hovered ? Tactile.keyTextHover : .secondary)
                .frame(width: 28, height: 26)
                .background(Color.white.opacity(hovered ? 0.12 : 0), in: RoundedRectangle(cornerRadius: 7, style: .circular))
                .contentShape(Rectangle())
        }
        .buttonStyle(StepPressStyle())
        .onHover { hovered = $0 }
    }
}

private struct StepPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.offset(y: configuration.isPressed ? 2 : 0)
    }
}

/// Поле в тёмной лунке, текст справа.
struct GlassField: View {
    @Binding var text: String
    var placeholder = ""
    var width: CGFloat = 150

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 12.5, design: .monospaced))
            .multilineTextAlignment(.trailing)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(width: width)
            .tactileWell(RoundedRectangle(cornerRadius: 8))
    }
}

/// Переключатель: синий во включённом виде, в лунке — в выключенном.
struct GlassSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) { configuration.isOn.toggle() } } label: {
            Capsule()
                .fill(configuration.isOn
                      ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0.35, green: 0.66, blue: 1), Color(red: 0.18, green: 0.49, blue: 0.94)],
                                                     startPoint: .top, endPoint: .bottom))
                      : AnyShapeStyle(Tactile.well.shadow(.inner(color: .black.opacity(0.6), radius: 2, y: 1))))
                .frame(width: 44, height: 26)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(LinearGradient(colors: [.white, Color(white: 0.88)], startPoint: .top, endPoint: .bottom))
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                        .padding(3)
                }
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "on" : "off")
    }
}

/// Горячая клавиша колпачками: «Записать» → поле мягко пульсирует и ждёт сочетания, Esc — отмена.
struct HotKeyCapsField: View {
    @Binding var spec: String
    let lang: String
    /// Пока идёт запись, Esc принадлежит записи, а не закрытию настроек.
    nonisolated(unsafe) static var isRecording = false

    @State private var recording = false
    @State private var pulse = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            if recording {
                Text(L.t("press_keys", lang))
                    .font(.system(size: 12.5))
                    .foregroundStyle(LayersPalette.accent)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(LayersPalette.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(LayersPalette.accent.opacity(pulse ? 0.8 : 0.4), lineWidth: pulse ? 2 : 1))
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pulse)
                    .onAppear { pulse = true }
                    .onDisappear { pulse = false }
            } else {
                HStack(spacing: 4) {
                    ForEach(Array(HotKeyCaps.keys(for: spec).enumerated()), id: \.offset) { index, key in
                        KeyCap(label: key)
                            .transition(.scale(scale: 0.6).combined(with: .opacity).animation(.spring(response: 0.3, dampingFraction: 0.6).delay(Double(index) * 0.06)))
                    }
                }
            }
            Button { recording ? stop() : start() } label: {
                Text(recording ? L.t("cancel", lang) : L.t("record", lang))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Tactile.keyText)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
            }
            .buttonStyle(KeyCapButtonStyle(cornerRadius: 14))
        }
        .onDisappear { stop() }
    }

    private func start() {
        withAnimation(.snappy) { recording = true }
        Self.isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil } // Esc — отмена
            if let chord = KeyChordFormatter.spec(modifiers: event.modifierFlags, keyCode: event.keyCode,
                                                   characters: event.charactersIgnoringModifiers) {
                withAnimation(.snappy) { spec = chord }
                stop()
            }
            return nil // нажатие не уходит дальше, пока идёт запись
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        Self.isRecording = false
        withAnimation(.snappy) { recording = false }
    }
}

private struct KeyCap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .frame(minWidth: 28, minHeight: 28)
            // в макете у клавиши и рамка, и внутренняя кромка — край в 2 точки
            .tactileRaised(RoundedRectangle(cornerRadius: 7, style: .circular), edgeWidth: 2)
    }
}

// MARK: - Приложения из поля ввода

extension SettingsView {
    /// Переключатели, алиасы (сгруппированы по приложению) и исключения.
    @ViewBuilder fileprivate var appRows: some View {
        row(L.t("open_apps", lang), hint: L.t("open_apps_hint", lang), first: true) {
            Toggle("", isOn: binding(\.openAppsFromInput)).toggleStyle(GlassSwitchStyle()).labelsHidden()
        }
        row(L.t("calculator", lang), hint: L.t("calculator_hint", lang)) {
            Toggle("", isOn: binding(\.calculatorInInput)).toggleStyle(GlassSwitchStyle()).labelsHidden()
        }
        if settings.calculatorInInput {
            row(L.t("calc_separator", lang), hint: L.t("calc_separator_hint", lang)) {
                GlassSegmented(options: [(".", "1.5"), (",", "1,5")], selection: binding(\.calculatorSeparator))
            }
            row(L.t("calc_force", lang), hint: L.t("calc_force_hint", lang)) {
                Toggle("", isOn: binding(\.calculatorForceSeparator)).toggleStyle(GlassSwitchStyle()).labelsHidden()
            }
        }
        row(L.t("app_aliases", lang), hint: L.t("app_aliases_hint", lang)) { newAliasControls }
        ForEach(aliasGroups, id: \.id) { entry in
            lineRow { aliasRow(entry.id, aliases: entry.aliases) }
        }
        row(L.t("app_exclusions", lang), hint: L.t("app_exclusions_hint", lang)) {
            GlassField(text: $exclusionDraft, placeholder: L.t("exclusion_placeholder", lang), width: 120)
                .onSubmit {
                    settings.addExclusion(exclusionDraft)
                    exclusionDraft = ""
                }
        }
        if !settings.appExclusions.isEmpty {
            lineRow {
                HStack(spacing: 6) {
                    ForEach(settings.appExclusions, id: \.self) { name in chip(name) { settings.removeExclusion(name) } }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// Строка группы без подписи слева: алиасы, поле нового алиаса, исключения.
    private func lineRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
            .overlay(alignment: .top) { Rectangle().fill(Tactile.groupEdge).frame(height: 1) }
    }

    /// Алиасы по приложениям: у VS Code — `code` и `vscode` в одной строке.
    fileprivate var aliasGroups: [(id: String, aliases: [String])] {
        Dictionary(grouping: settings.appAliases.keys, by: { settings.appAliases[$0] ?? "" })
            .map { (id: $0.key, aliases: $0.value.sorted()) }
            .sorted { appTitle($0.id).localizedCaseInsensitiveCompare(appTitle($1.id)) == .orderedAscending }
    }

    private func app(_ id: String) -> AppEntry? { AppCatalog.shared.apps.first { $0.identifier == id } }

    private func appTitle(_ id: String) -> String { app(id)?.title ?? id }

    private func aliasRow(_ id: String, aliases: [String]) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(aliases, id: \.self) { alias in chip(alias) { settings.removeAlias(alias) } }
            }
            Text("→").foregroundStyle(.tertiary)
            if let app = app(id) {
                AppIconView(app: app)
                Text(app.title).font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
            } else {
                Text(id).font(.system(size: 12)).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                Text(L.t("app_missing", lang)).font(.system(size: 11)).foregroundStyle(.tertiary).fixedSize()
            }
            Spacer(minLength: 0)
        }
    }

    /// Новый алиас: набрать имя и выбрать приложение из списка.
    private var newAliasControls: some View {
        HStack(spacing: 6) {
            GlassField(text: $aliasDraft, placeholder: L.t("alias_placeholder", lang), width: 90)
            AppPickerButton(title: L.t("alias_pick_app", lang), apps: AppCatalog.shared.apps,
                            enabled: !aliasDraft.trimmingCharacters(in: .whitespaces).isEmpty, lang: lang) { app in
                settings.setAlias(aliasDraft, for: app.identifier)
                aliasDraft = ""
            }
        }
    }

    private func chip(_ text: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 3) {
            Text(text).font(.system(size: 12, design: .monospaced))
            Button(action: onRemove) {
                Text("×").font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 14, height: 14).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L.t("remove", lang))
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .frame(height: 22)
        .background(Tactile.accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Tactile.accent.opacity(0.6), lineWidth: 0.5))
        .fixedSize()
    }
}

// MARK: - Буфер обмена

extension SettingsView {
    @ViewBuilder fileprivate var clipboardRows: some View {
        row(L.t("clipboard", lang), hint: L.t("clipboard_hint", lang), first: true) {
            Toggle("", isOn: binding(\.clipboardEnabled)).toggleStyle(GlassSwitchStyle()).labelsHidden()
        }
        row(L.t("clipboard_days", lang), hint: L.t("clipboard_days_hint", lang)) {
            GlassStepper(value: binding(\.clipboardDays), range: SettingsStore.clipboardDaysRange)
        }
        row(L.t("clipboard_images", lang), hint: L.t("clipboard_images_hint", lang)) {
            Toggle("", isOn: binding(\.clipboardImages)).toggleStyle(GlassSwitchStyle()).labelsHidden()
        }
        if settings.clipboardImages {
            row(L.t("clipboard_ocr", lang), hint: L.t("clipboard_ocr_hint", lang)) {
                Toggle("", isOn: binding(\.clipboardRecognizeText)).toggleStyle(GlassSwitchStyle()).labelsHidden()
            }
        }
        row(L.t("clipboard_excluded", lang), hint: L.t("clipboard_excluded_hint", lang)) {
            AppPickerButton(title: L.t("clipboard_add_app", lang),
                            apps: AppCatalog.shared.apps.filter { $0.bundleID != nil }, lang: lang) { app in
                settings.addClipboardExclusion(app.bundleID ?? "")
            }
        }
        if !settings.clipboardExcludedApps.isEmpty {
            lineRow {
                ExcludedAppsFlow(ids: settings.clipboardExcludedApps, lang: lang) { settings.removeClipboardExclusion($0) }
            }
        }
        row(L.t("clipboard_clear_title", lang), hint: String(format: L.t("clip_count", lang), clipboard.clips.count)) {
            Button { clipboard.clear() } label: {
                Text(L.t("clipboard_clear", lang))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Tactile.redText)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
            }
            .buttonStyle(KeyCapButtonStyle(cornerRadius: 8))
            .disabled(clipboard.clips.isEmpty)
        }
    }
}

// MARK: - Скриншоты

extension SettingsView {
    @ViewBuilder fileprivate var screenshotRows: some View {
        row(L.t("screenshots", lang), hint: L.t("screenshots_hint", lang), first: true) {
            Toggle("", isOn: binding(\.screenshotsEnabled)).toggleStyle(GlassSwitchStyle()).labelsHidden()
        }
        if settings.screenshotsEnabled {
            row(L.t("screenshot_shortcut", lang), hint: L.t("screenshot_shortcut_hint", lang)) {
                HotKeyCapsField(spec: binding(\.screenshotShortcut), lang: lang)
            }
            if screenshotTaken {
                lineRow {
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(String(format: L.t("screenshot_taken", lang), SystemScreenshotShortcuts.display(settings.screenshotShortcut)))
                            .font(.system(size: 11.5))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Button { SystemScreenshotShortcuts.openKeyboardSettings() } label: {
                            Text(L.t("screenshot_open_settings", lang))
                                .font(.system(size: 12.5, weight: .semibold))
                                .padding(.horizontal, 12)
                                .frame(height: 28)
                        }
                        .buttonStyle(KeyCapButtonStyle(cornerRadius: 8))
                        .fixedSize()
                    }
                    .padding(.vertical, 9)
                }
            }
            row(L.t("screenshot_seconds", lang)) {
                GlassStepper(value: binding(\.screenshotThumbnailSeconds), range: SettingsStore.screenshotSecondsRange)
            }
            row(L.t("screen_recording", lang), hint: L.t("screen_recording_hint", lang)) {
                if screenRecordingAllowed {
                    Label(L.t("screen_recording_ok", lang), systemImage: "checkmark")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.green)
                } else {
                    Button {
                        // первый раз macOS спросит сама; если уже отказали — открыть раздел конфиденциальности
                        if !CGRequestScreenCaptureAccess(),
                           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Text(L.t("screen_recording_allow", lang))
                            .font(.system(size: 12.5, weight: .semibold))
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                    }
                    .buttonStyle(KeyCapButtonStyle(cornerRadius: 8))
                }
            }
        }
    }
}

/// Приложения-исключения буфера: значок и имя, «×» убирает.
private struct ExcludedAppsFlow: View {
    let ids: [String]
    let lang: String
    var onRemove: (String) -> Void

    var body: some View {
        // чипы переносятся по ширине листа: иначе длинный ряд раздвигал настройки вбок
        FlowLayout(spacing: 6) {
            ForEach(ids, id: \.self) { id in chip(id) }
        }
        .padding(.vertical, 8)
    }

    private func chip(_ id: String) -> some View {
        HStack(spacing: 4) {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 14, height: 14)
            }
            Text(Self.name(id)).font(.system(size: 12)).lineLimit(1)
            Button { onRemove(id) } label: {
                Text("×").font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 14, height: 14).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L.t("remove", lang))
        }
        .padding(.leading, 6)
        .padding(.trailing, 4)
        .frame(height: 22)
        .background(Tactile.accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Tactile.accent.opacity(0.6), lineWidth: 0.5))
        .fixedSize()
    }

    private static let knownNames = ["com.1password.1password": "1Password", "com.agilebits.onepassword7": "1Password 7"]

    /// Имя приложения: из списка установленных, иначе по bundle id.
    static func name(_ id: String) -> String {
        if let app = AppCatalog.shared.apps.first(where: { $0.bundleID == id }) { return app.title }
        // менеджеры паролей из списка по умолчанию — по имени, даже если не установлены
        if let known = knownNames[id] { return known }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return id
    }
}

/// Раскладка «как текст»: элементы в строку, не влезло — на следующую.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews, width: width)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let used = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? used, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var items: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = row.items.isEmpty ? size.width : row.width + spacing + size.width
            if !row.items.isEmpty, needed > width {
                rows.append(row)
                row = Row(y: row.y + row.height + spacing)
            }
            row.width = row.items.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.items.append(index)
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}
