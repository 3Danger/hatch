import SwiftUI
import AppKit

/// Настройки — ещё один слой стекла поверх панели (панель за ним отходит назад).
/// Горячая клавиша колпачками с записью, тема и язык сегментами, глубина истории счётчиком.
struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    var onClose: () -> Void = {}

    private var lang: String { settings.languageCode }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L.t("settings", lang)).font(.system(size: 16, weight: .semibold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .help(L.t("close", lang))
                .accessibilityLabel(L.t("close", lang))
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)

            group {
                row(L.t("hotkey", lang), first: true) { HotKeyCapsField(spec: binding(\.hotkeyString), lang: lang) }
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

            HStack {
                Text("Hatch \(version)").font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button(action: onClose) {
                    Text(L.t("done", lang))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(height: 32)
                        .background(
                            LinearGradient(colors: [Color(red: 0.47, green: 0.75, blue: 1).opacity(0.6),
                                                    Color(red: 0.24, green: 0.51, blue: 0.94).opacity(0.5)],
                                           startPoint: .top, endPoint: .bottom),
                            in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
                        .shadow(color: Color(red: 0.24, green: 0.55, blue: 1).opacity(0.5), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 14)
        }
        .frame(width: 440)
        .background(
            LinearGradient(colors: [.white.opacity(0.14), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 22))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.16)))
        .shadow(color: .black.opacity(0.55), radius: 30, y: 18)
    }

    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.07)))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
    }

    private func row<Control: View>(_ title: String, first: Bool = false, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 12) {
            Text(title).font(.system(size: 13.5))
            Spacer(minLength: 8)
            control()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 46)
        .overlay(alignment: .top) { if !first { Rectangle().fill(.white.opacity(0.07)).frame(height: 1) } }
    }

    private func binding<T>(_ keyPath: ReferenceWritableKeyPath<SettingsStore, T>) -> Binding<T> {
        Binding(get: { settings[keyPath: keyPath] }, set: { settings[keyPath: keyPath] = $0 })
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
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.id) { option in
                let selected = option.id == selection
                Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { selection = option.id } } label: {
                    Text(option.title)
                        .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? .primary : .secondary)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(LinearGradient(colors: [.white.opacity(0.24), .white.opacity(0.1)],
                                                         startPoint: .top, endPoint: .bottom))
                                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.white.opacity(0.22), lineWidth: 0.5))
                                    .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
                                    .matchedGeometryEffect(id: "segment", in: namespace)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 10))
    }
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
                .font(.system(size: 13.5, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(value)))
                .frame(width: 44)
            stepButton("plus", delta: step)
        }
        .padding(3)
        .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 10))
    }

    private func stepButton(_ symbol: String, delta: Int) -> some View {
        Button {
            let next = min(max(value + delta, range.lowerBound), range.upperBound)
            withAnimation(.snappy) { value = next }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
            .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Стеклянный переключатель: синий со свечением во включённом виде.
struct GlassSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) { configuration.isOn.toggle() } } label: {
            Capsule()
                .fill(configuration.isOn
                      ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0.35, green: 0.66, blue: 1), Color(red: 0.18, green: 0.49, blue: 0.94)],
                                                     startPoint: .top, endPoint: .bottom))
                      : AnyShapeStyle(Color.black.opacity(0.35)))
                .frame(width: 44, height: 26)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(LinearGradient(colors: [.white, Color(white: 0.88)], startPoint: .top, endPoint: .bottom))
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                        .padding(3)
                }
                .shadow(color: configuration.isOn ? Color(red: 0.3, green: 0.6, blue: 1).opacity(0.55) : .clear, radius: 7)
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
            Button(recording ? L.t("cancel", lang) : L.t("record", lang)) { recording ? stop() : start() }
                .buttonStyle(.plain)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color(red: 0.84, green: 0.92, blue: 1))
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(LayersPalette.accent.opacity(0.18), in: Capsule())
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
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .frame(minWidth: 28, minHeight: 28)
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(LinearGradient(colors: [.white.opacity(0.2), .white.opacity(0.07)], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.white.opacity(0.18)))
                    .shadow(color: .black.opacity(0.35), radius: 0, y: 2) // тень только у колпачка, не у текста
            }
    }
}
