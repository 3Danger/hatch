import Foundation
import Carbon

/// Классические Carbon-маски модификаторов (используются RegisterEventHotKey).
enum CarbonModifiers {
    static let control: UInt32 = 4096
    static let shift: UInt32 = 512
    static let option: UInt32 = 2048
    static let command: UInt32 = 256
}

/// Разобранное сочетание клавиш (keyCode + маска модификаторов Carbon).
struct KeyBinding: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
}

/// Парсер строкового описания хоткей, например "ctrl-space", "cmd-shift-a".
enum KeyBindingParser {
    static let spaceKeyCode: UInt32 = 49  // kVK_Space
    static let returnKeyCode: UInt32 = 36 // kVK_Return
    static let tabKeyCode: UInt32 = 48    // kVK_Tab
    static let escapeKeyCode: UInt32 = 53 // kVK_Escape
    /// Цифра → код клавиши (kVK_ANSI_0…9): по порядку идут только 1–4.
    static let digitKeyCodes: [Int: UInt32] = [1: 18, 2: 19, 3: 20, 4: 21, 5: 23, 6: 22, 7: 26, 8: 28, 9: 25, 0: 29]

    static func parse(_ spec: String) -> KeyBinding? {
        let parts = spec.lowercased().split(separator: "-").map(String.init)
        guard !parts.isEmpty else { return nil }

        var modifiers: UInt32 = 0
        var keyName: String?

        for part in parts {
            switch part {
            case "ctrl", "control":
                modifiers |= CarbonModifiers.control
            case "cmd", "command":
                modifiers |= CarbonModifiers.command
            case "shift":
                modifiers |= CarbonModifiers.shift
            case "alt", "option":
                modifiers |= CarbonModifiers.option
            default:
                guard keyName == nil else { return nil } // больше одного ключа
                keyName = part
            }
        }

        guard let name = keyName else { return nil }

        let keyCode: UInt32?
        switch name {
        case "space":
            keyCode = spaceKeyCode
        case "return", "enter":
            keyCode = returnKeyCode
        case "tab":
            keyCode = tabKeyCode
        case "escape", "esc":
            keyCode = escapeKeyCode
        default:
            if name.count == 1, let scalar = name.unicodeScalars.first {
                let value = Int(scalar.value)
                if (97...122).contains(value) {
                    keyCode = UInt32(value - 97) // kVK_ANSI_A == 0
                } else if (48...57).contains(value) {
                    keyCode = digitKeyCodes[value - 48]
                } else {
                    keyCode = nil
                }
            } else {
                keyCode = nil
            }
        }

        guard let code = keyCode else { return nil }
        return KeyBinding(keyCode: code, modifiers: modifiers)
    }
}

/// Объект-приёмник срабатывания глобального хоткей.
protocol HotKeyDelegate: AnyObject {
    func hotKeyPressed()
}

/// Менеджер глобальных хоткеев на Carbon (RegisterEventHotKey): несколько сочетаний, у каждого свой номер.
/// Номер 1 — панель (делегат), остальные — свои действия (`handlers`), например снимок экрана.
final class HotKeyManager {
    fileprivate let signature: OSType = 0x4D554B53 // 'MUKS'
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private weak var delegate: HotKeyDelegate?
    /// Действия сочетаний кроме панели: номер → что сделать.
    var handlers: [UInt32: () -> Void] = [:]

    init(delegate: HotKeyDelegate) {
        self.delegate = delegate
    }

    deinit {
        for id in hotKeyRefs.keys { unregister(identifier: id) }
        removeEventHandler()
    }

    /// Регистрирует хоткей под номером (прежний с тем же номером снимается). Возвращает true при успехе.
    @discardableResult
    func register(_ binding: KeyBinding, identifier: UInt32 = 1) -> Bool {
        unregister(identifier: identifier)

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: identifier)
        let status = RegisterEventHotKey(binding.keyCode,
                                         binding.modifiers,
                                         hotKeyID,
                                         GetEventDispatcherTarget(),
                                         0,
                                         &hotKeyRef)
        guard status == noErr, let hotKeyRef else { return false }
        hotKeyRefs[identifier] = hotKeyRef

        if eventHandlerRef == nil {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                          eventKind: UInt32(kEventHotKeyPressed))
            let installStatus = InstallEventHandler(GetEventDispatcherTarget(),
                                                    hotKeyEventHandler,
                                                    1,
                                                    &eventType,
                                                    Unmanaged.passUnretained(self).toOpaque(),
                                                    &eventHandlerRef)
            guard installStatus == noErr else {
                unregister(identifier: identifier)
                return false
            }
        }
        return true
    }

    func unregister(identifier: UInt32 = 1) {
        if let hotKeyRef = hotKeyRefs.removeValue(forKey: identifier) {
            UnregisterEventHotKey(hotKeyRef)
        }
    }

    private func removeEventHandler() {
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    fileprivate func handlePress(id: UInt32) {
        if let handler = handlers[id] { handler() } else { delegate?.hotKeyPressed() }
    }
}

private func hotKeyEventHandler(_ nextHandler: EventHandlerCallRef?,
                                _ event: EventRef?,
                                _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let userData, let event else { return noErr }

    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event,
                                   EventParamName(kEventParamDirectObject),
                                   EventParamType(typeEventHotKeyID),
                                   nil,
                                   MemoryLayout<EventHotKeyID>.size,
                                   nil,
                                   &hotKeyID)
    guard status == noErr else { return status }

    if hotKeyID.signature == manager.signature {
        manager.handlePress(id: hotKeyID.id)
    }
    return noErr
}
