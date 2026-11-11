import Carbon

/// Источник ввода macOS (раскладка): то, что нужно переключателю. В тестах — подставной.
protocol InputSourceBackend {
    func currentID() -> String?
    func currentIsASCIICapable() -> Bool
    /// Включить латинскую раскладку из добавленных пользователем (последнюю использованную).
    func selectASCIICapable() -> Bool
    func select(id: String) -> Bool
}

/// Латиница в поле ввода команды: при фокусе включает латинскую раскладку из тех,
/// что есть у пользователя; при скрытии панели возвращает прежнюю — если пользователь
/// сам за это время её не сменил. Раскладка в macOS общая для всех приложений,
/// поэтому без возврата русская пропадала бы и в других окнах.
final class KeyboardLayoutSwitcher {
    /// Под тестами приложение тоже показывает панель — раскладку пользователя не трогаем.
    static let shared = KeyboardLayoutSwitcher(
        backend: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
            ? TISInputSourceBackend() : InertInputSourceBackend())

    private let backend: InputSourceBackend
    /// Раскладка до первого переключения — её вернём при скрытии.
    private var originalID: String?
    /// Раскладка, которую включили мы; если при скрытии стоит другая — её выбрал пользователь.
    private var switchedToID: String?

    init(backend: InputSourceBackend) {
        self.backend = backend
    }

    func switchToLatin() {
        guard !backend.currentIsASCIICapable() else { return }
        let previous = backend.currentID()
        guard backend.selectASCIICapable() else { return }
        if originalID == nil { originalID = previous }
        switchedToID = backend.currentID()
    }

    func restore() {
        defer {
            originalID = nil
            switchedToID = nil
        }
        guard let originalID, let switchedToID, backend.currentID() == switchedToID else { return }
        _ = backend.select(id: originalID)
    }
}

/// Text Input Sources (Carbon): раскладки, включённые пользователем в системных настройках.
struct TISInputSourceBackend: InputSourceBackend {
    func currentID() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return Self.string(source, kTISPropertyInputSourceID)
    }

    func currentIsASCIICapable() -> Bool {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return true }
        return Self.bool(source, kTISPropertyInputSourceIsASCIICapable)
    }

    func selectASCIICapable() -> Bool {
        // последняя использованная латинская раскладка из добавленных пользователем
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              Self.bool(source, kTISPropertyInputSourceIsEnabled) else { return false }
        return TISSelectInputSource(source) == noErr
    }

    func select(id: String) -> Bool {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource],
              let source = list.first else { return false }
        return TISSelectInputSource(source) == noErr
    }

    private static func string(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    private static func bool(_ source: TISInputSource, _ key: CFString) -> Bool {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue())
    }
}

/// Ничего не переключает: для запуска под тестами.
struct InertInputSourceBackend: InputSourceBackend {
    func currentID() -> String? { nil }
    func currentIsASCIICapable() -> Bool { true }
    func selectASCIICapable() -> Bool { false }
    func select(id: String) -> Bool { false }
}
