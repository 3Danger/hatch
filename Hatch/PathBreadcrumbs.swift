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
}
