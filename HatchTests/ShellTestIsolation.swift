import Foundation

/// Тесты не зависят от `~/.zshrc` пользователя: его загрузка может зависнуть
/// (запрос доступа macOS к ~/Desktop, сеть, медленные плагины) и менять поведение команд.
/// ZDOTDIR указывает на пустую папку — шелл берёт rc-файлы оттуда.
enum ShellTestIsolation {
    private static let emptyZDOTDIR: String = {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hatch-tests-zdotdir", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }()

    static func apply() {
        setenv("ZDOTDIR", emptyZDOTDIR, 1)
    }
}
