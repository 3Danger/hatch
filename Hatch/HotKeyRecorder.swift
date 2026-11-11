import SwiftUI
import AppKit

/// Преобразует нажатие клавиш в строковое описание хоткей (напр. "cmd-shift-a").
enum KeyChordFormatter {
    static func spec(modifiers: NSEvent.ModifierFlags, keyCode: UInt16, characters: String?) -> String? {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("ctrl") }
        if modifiers.contains(.command) { parts.append("cmd") }
        if modifiers.contains(.shift) { parts.append("shift") }
        if modifiers.contains(.option) { parts.append("alt") }

        var base: String?
        switch Int(keyCode) {
        case 49:
            base = "space"
        case 36:
            base = "return"
        case 48:
            base = "tab"
        case 53:
            base = "escape"
        case 51:
            base = "delete"
        case 18...27:
            // ANSI-цифры: 18='1' … 26='9', 27='0'
            let n = Int(keyCode)
            base = n == 27 ? "0" : "\(n - 18 + 1)"
        default:
            // буквы/цифры берём из characters (учитывает раскладку)
            if let ch = characters?.lowercased(), ch.count == 1,
               let scalar = ch.unicodeScalars.first {
                let value = Int(scalar.value)
                if (97...122).contains(value) || (48...57).contains(value) {
                    base = ch
                }
            }
        }

        guard let key = base, !parts.isEmpty else { return nil }
        parts.append(key)
        return parts.joined(separator: "-")
    }
}

/// Поле записи горячей клавиши: клик «Записать» → нажатие → «Готово».
struct HotKeyField: View {
    @Binding var spec: String
    let lang: String

    @State private var recording = false
    @State private var preview = ""
    @State private var monitorToken: Any?

    var body: some View {
        HStack(spacing: 8) {
            if recording {
                Text(preview.isEmpty ? "Нажми сочетание…" : preview)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(preview.isEmpty ? Color.secondary : Color.primary)

                Button("Готово") { commit() }
                    .disabled(preview.isEmpty)

                Button("Отмена") { stop() }
            } else {
                Text(spec.isEmpty ? "—" : spec)
                    .font(.system(.body, design: .monospaced))

                Button("Записать") { start() }
            }
        }
        .onDisappear { stop() } // гарантированно снимаем монитор при закрытии
    }

    private func start() {
        recording = true
        preview = ""
        monitorToken = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard self.recording else { return event }
            if let s = KeyChordFormatter.spec(modifiers: event.modifierFlags,
                                              keyCode: event.keyCode,
                                              characters: event.charactersIgnoringModifiers) {
                self.preview = s
            }
            return nil // потребляем нажатие, чтобы оно не уходило дальше
        }
    }

    private func commit() {
        if !preview.isEmpty {
            spec = preview
        }
        stop()
    }

    private func stop() {
        recording = false
        if let token = monitorToken {
            NSEvent.removeMonitor(token)
            monitorToken = nil
        }
    }
}
