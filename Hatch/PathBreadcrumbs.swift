import Foundation

/// Путь «хлебными крошками»: `~ / tmp / Hatch` — у каждой части свой полный путь.
enum PathBreadcrumbs {
    struct Crumb: Equatable {
        let title: String
        let path: String
    }

    static func segments(for path: String, home: String = SettingsStore.homeDirectory) -> [Crumb] {
        var crumbs: [Crumb]
        var current: String
        let rest: String
        if path == home || path.hasPrefix(home + "/") {
            crumbs = [Crumb(title: "~", path: home)]
            current = home
            rest = String(path.dropFirst(home.count))
        } else {
            crumbs = [Crumb(title: "/", path: "/")]
            current = ""
            rest = path
        }
        for part in rest.split(separator: "/") {
            current += "/" + part
            crumbs.append(Crumb(title: String(part), path: current))
        }
        return crumbs
    }

    /// Имя папки для заголовка блока: `Hatch`, `~` для домашней, `/` для корня.
    static func folderName(for path: String, home: String = SettingsStore.homeDirectory) -> String {
        segments(for: path, home: home).last?.title ?? path
    }

    /// Путь коротко, с `~` вместо домашней папки: `~/tmp/Hatch`, `/usr/local`.
    static func displayPath(for path: String, home: String = SettingsStore.homeDirectory) -> String {
        let titles = segments(for: path, home: home).map(\.title)
        guard let first = titles.first else { return path }
        let rest = titles.dropFirst().joined(separator: "/")
        if rest.isEmpty { return first }
        return first == "/" ? "/" + rest : first + "/" + rest
    }
}
