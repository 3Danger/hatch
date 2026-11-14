import AppKit
import ApplicationServices

/// Вставка записи буфера туда, где был пользователь: Enter в буфере копирует запись, прячет панель
/// и нажимает ⌘V в приложении, которое было впереди до Hatch (как Raycast, Alfred, Maccy).
/// Нажатие за пользователя требует права «Универсальный доступ»; без него Enter только копирует.
enum PasteBack {
    /// Приложение, которое было впереди, когда показали панель (Hatch не в счёт).
    private(set) static var target: NSRunningApplication?

    /// Запомнить, куда вставлять: вызывается перед показом панели.
    static func rememberFrontmost(_ app: NSRunningApplication? = NSWorkspace.shared.frontmostApplication) {
        guard let app, app.bundleIdentifier != Bundle.main.bundleIdentifier, app.processIdentifier != getpid() else { return }
        target = app
    }

    /// Имя приложения для подписи кнопки: «вставить в Terminal».
    static var targetName: String? { target?.localizedName }

    /// Есть ли право нажимать клавиши за пользователя.
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Системный запрос права (открывает «Универсальный доступ» с Hatch в списке).
    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Можно ли вставить сразу: есть право и куда (приложение ещё работает).
    static var canPaste: Bool { isTrusted && target?.isTerminated == false }

    /// Панель уже спрятана: вернуть приложение вперёд и нажать ⌘V, когда оно станет активным.
    static func pasteIntoTarget() {
        guard canPaste, let target else { return }
        if !target.isActive { target.activate() }
        // приложению нужно мгновение, чтобы стать активным и принять нажатие
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { postCommandV() }
    }

    /// ⌘V как от клавиатуры: по коду клавиши V (в любой раскладке ⌘V — «вставить»).
    private static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyV: CGKeyCode = 9
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: down)
            event?.flags = .maskCommand
            event?.post(tap: .cgAnnotatedSessionEventTap)
        }
    }
}
