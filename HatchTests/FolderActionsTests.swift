import XCTest
import AppKit
@testable import Hatch

/// Общие действия с папкой: одни и те же пункты в меню пути и в меню дерева.
@MainActor
final class FolderActionsTests: XCTestCase {
    private func titles(_ folder: String, current: String, favorites: [String] = []) -> [[String]] {
        let context = PopupContext(anchorView: NSView(), dismiss: {})
        return FolderActions.sections(for: folder, currentDirectory: current, favorites: favorites, lang: "ru",
                                      context: context, close: {}, onToggleFavorite: { _ in }, onCopied: {})
            .map { $0.items.map(\.title) }
    }

    func testSectionsForFolder() {
        XCTAssertEqual(titles("/tmp/a", current: "/tmp"), [
            [L.t("fav_add", "ru")],
            [L.t("open_in_finder", "ru"), L.t("open_in_editor", "ru"), L.t("copy_path", "ru"), L.t("share", "ru")],
        ])
        XCTAssertEqual(titles("/tmp/a", current: "/tmp", favorites: ["/tmp/a"])[0], [L.t("fav_remove", "ru")])
    }

    /// ⌘D подписан только у текущей папки: сочетание действует на неё.
    func testShortcutHintOnlyForCurrentFolder() {
        let context = PopupContext(anchorView: NSView(), dismiss: {})
        func favoriteDetail(_ folder: String) -> String? {
            FolderActions.sections(for: folder, currentDirectory: "/tmp", favorites: [], lang: "ru", context: context,
                                   close: {}, onToggleFavorite: { _ in }, onCopied: {})[0].items[0].detail
        }
        XCTAssertEqual(favoriteDetail("/tmp"), "⌘D")
        XCTAssertNil(favoriteDetail("/tmp/a"))
    }

    /// «Добавить в избранное» сначала закрывает меню, потом меняет избранное — для этой папки.
    func testFavoriteActionClosesMenuAndToggles() {
        var log: [String] = []
        let sections = FolderActions.sections(for: "/tmp/a", currentDirectory: "/tmp", favorites: [], lang: "ru",
                                              context: PopupContext(anchorView: NSView(), dismiss: {}),
                                              close: { log.append("close") }, onToggleFavorite: { log.append("fav \($0)") },
                                              onCopied: {})
        sections[0].items[0].action?()
        XCTAssertEqual(log, ["close", "fav /tmp/a"])
    }
}
