import AppKit

/// Один Hatch на компьютере: запущенная новая сборка закрывает уже работающую.
/// Иначе старый процесс остаётся висеть со своей горячей клавишей и значком.
enum SingleInstance {
    /// Сколько ждать, пока старый экземпляр допишет историю и отпустит горячую клавишу.
    static let waitLimit: TimeInterval = 3

    static func terminateOthers(bundleID: String? = Bundle.main.bundleIdentifier) {
        guard let bundleID else { return }
        let others = others(of: bundleID)
        guard !others.isEmpty else { return }
        others.forEach { $0.terminate() }
        // старый при выходе пишет историю на диск — новый должен прочитать её уже после этого
        let deadline = Date().addingTimeInterval(waitLimit)
        while Date() < deadline, others.contains(where: { !$0.isTerminated }) {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        others.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
    }

    private static func others(of bundleID: String) -> [NSRunningApplication] {
        let me = NSRunningApplication.current.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != me }
    }
}
