import XCTest
import SwiftUI
@testable import Hatch

/// Дерево папок у пути: клавиши как в хлебных крошках VS Code, Enter — переход, ← на верху — уровнем выше.
final class FolderTreeTests: XCTestCase {
    private let fs: [String: [String]] = [
        "/": ["Users", "usr"],
        "/Users": ["me"],
        "/Users/me": ["git", "tmp"],
        "/Users/me/git": ["go-wallets", "hatch", "kafka-tools"],
        "/Users/me/git/go-wallets": ["cmd", "internal", "wallet"],
        "/Users/me/git/go-wallets/wallet": ["cmd", "internal"],
        "/Users/me/git/go-wallets/wallet/internal": ["api"],
    ]
    private var children: FolderTree.Children { { self.fs[$0] ?? [] } }

    private func names(_ tree: FolderTree) -> [String] { tree.rows(children).map(\.name) }

    func testOpensOnSiblingsWithFolderSelected() {
        let tree = FolderTree(crumb: "/Users/me/git/go-wallets/wallet")
        XCTAssertEqual(tree.root, "/Users/me/git/go-wallets")
        XCTAssertEqual(names(tree), ["cmd", "internal", "wallet"])
        XCTAssertEqual(tree.focus, "/Users/me/git/go-wallets/wallet")
    }

    func testRootCrumbShowsItsFolders() {
        let tree = FolderTree(crumb: "/")
        XCTAssertEqual(tree.root, "/")
        XCTAssertEqual(names(tree), ["Users", "usr"])
        XCTAssertNil(tree.focus)
    }

    func testUpDownStayInBounds() {
        var tree = FolderTree(crumb: "/Users/me/git/go-wallets/wallet")
        tree.handle(.down, children: children)
        XCTAssertEqual(tree.focus, "/Users/me/git/go-wallets/wallet") // последняя строка
        tree.handle(.up, children: children)
        tree.handle(.up, children: children)
        tree.handle(.up, children: children)
        XCTAssertEqual(tree.focus, "/Users/me/git/go-wallets/cmd") // первая
    }

    /// → раскрывает, второе → входит в первую вложенную.
    func testRightExpandsThenEnters() {
        var tree = FolderTree(crumb: "/Users/me/git/go-wallets/wallet")
        tree.handle(.right, children: children)
        XCTAssertTrue(tree.isExpanded("/Users/me/git/go-wallets/wallet"))
        XCTAssertEqual(names(tree), ["cmd", "internal", "wallet", "cmd", "internal"])
        tree.handle(.right, children: children)
        XCTAssertEqual(tree.focus, "/Users/me/git/go-wallets/wallet/cmd")
    }

    /// ← сворачивает раскрытую, у вложенной — к родителю.
    func testLeftCollapsesOrGoesToParent() {
        var tree = FolderTree(crumb: "/Users/me/git/go-wallets/wallet")
        tree.handle(.right, children: children)
        tree.handle(.right, children: children)
        tree.handle(.down, children: children) // wallet/internal
        tree.handle(.right, children: children) // раскрыть internal
        tree.handle(.left, children: children)  // свернуть internal
        XCTAssertFalse(tree.isExpanded("/Users/me/git/go-wallets/wallet/internal"))
        tree.handle(.left, children: children)  // к родителю
        XCTAssertEqual(tree.focus, "/Users/me/git/go-wallets/wallet")
        tree.handle(.left, children: children)  // свернуть wallet
        XCTAssertFalse(tree.isExpanded("/Users/me/git/go-wallets/wallet"))
    }

    /// ← на верхнем уровне — дерево уровнем выше, папка выделена, подсветка в пути переезжает.
    func testLeftAtTopLiftsTreeUp() {
        var tree = FolderTree(crumb: "/Users/me/git/go-wallets/wallet")
        tree.handle(.left, children: children)
        XCTAssertEqual(tree.root, "/Users/me/git")
        XCTAssertEqual(tree.focus, "/Users/me/git/go-wallets")
        XCTAssertEqual(tree.crumb, "/Users/me/git/go-wallets")
        XCTAssertEqual(names(tree), ["go-wallets", "hatch", "kafka-tools"])
        // до корня и не дальше
        for _ in 0..<10 { tree.handle(.left, children: children) }
        XCTAssertEqual(tree.root, "/")
        XCTAssertEqual(tree.focus, "/Users")
    }

    /// Свернуть папку, внутри которой выделение, — выделение на ней самой.
    func testSpaceTogglesAndKeepsSelectionVisible() {
        var tree = FolderTree(crumb: "/Users/me/git/go-wallets/wallet")
        tree.handle(.space, children: children)
        tree.handle(.right, children: children) // внутрь
        XCTAssertEqual(tree.focus, "/Users/me/git/go-wallets/wallet/cmd")
        tree.toggle("/Users/me/git/go-wallets/wallet") // клик по шеврону
        XCTAssertEqual(tree.focus, "/Users/me/git/go-wallets/wallet")
        XCTAssertFalse(tree.isExpanded("/Users/me/git/go-wallets/wallet"))
    }

    func testEnterNavigatesToSelected() {
        var tree = FolderTree(crumb: "/Users/me/git/go-wallets/wallet")
        tree.handle(.up, children: children)
        XCTAssertEqual(tree.enter(), .navigate("/Users/me/git/go-wallets/internal"))
    }

    /// Буквы фильтруют видимые строки: совпавшие и (бледно) их родители; выделение — на лучшее совпадение.
    func testFilterKeepsMatchesAndTheirParents() {
        var tree = FolderTree(crumb: "/Users/me/git/go-wallets")
        tree.handle(.right, children: children) // раскрыть go-wallets
        tree.handle(.right, children: children) // войти в cmd
        tree.handle(.down, children: children)
        tree.handle(.down, children: children) // wallet
        tree.handle(.right, children: children) // раскрыть wallet
        tree.handle(.character("i"), children: children)
        tree.handle(.character("n"), children: children)
        let visible = tree.visibleRows(children)
        XCTAssertEqual(visible.filter { !$0.isContext }.map(\.row.name), ["internal", "internal"])
        XCTAssertEqual(visible.filter(\.isContext).map(\.row.name), ["go-wallets", "wallet"])
        XCTAssertEqual(tree.focus, "/Users/me/git/go-wallets/internal")
        tree.handle(.down, children: children) // ↓ — по совпавшим, мимо родителей
        XCTAssertEqual(tree.focus, "/Users/me/git/go-wallets/wallet/internal")
    }

    func testFilterRanksNamePrefixFirstAndClears() {
        var tree = FolderTree(crumb: "/Users/me/git/hatch")
        tree.handle(.character("t"), children: children) // «kafka-tools» — с начала слова, «hatch» — внутри
        XCTAssertEqual(tree.focus, "/Users/me/git/kafka-tools")
        XCTAssertEqual(tree.filter, "t")
        tree.handle(.backspace(all: false), children: children)
        XCTAssertEqual(tree.filter, "")
        tree.handle(.character("з"), children: children) // русская раскладка: «з» — это «p»
        XCTAssertEqual(tree.filter, "з")
        XCTAssertTrue(tree.clearFilter())
        XCTAssertFalse(tree.clearFilter(), "второй Esc — фильтра уже нет: закрыть дерево")
    }

    /// → снимает фильтр и раскрывает выделенную папку, как без фильтра.
    func testArrowRightLeavesFilter() {
        var tree = FolderTree(crumb: "/Users/me/git/hatch")
        tree.handle(.character("g"), children: children)
        XCTAssertEqual(tree.focus, "/Users/me/git/go-wallets")
        tree.handle(.right, children: children)
        XCTAssertEqual(tree.filter, "")
        XCTAssertTrue(tree.isExpanded("/Users/me/git/go-wallets"))
    }

    /// Где в пути папка дерева: в пути — её место; выше начала пути (выше ~) — «левее первой».
    func testTreeIndexInPath() {
        let paths = ["/Users/me", "/Users/me/git", "/Users/me/git/hatch"]
        XCTAssertEqual(DirectoryBreadcrumbsView.treeIndex(of: "/Users/me/git", in: paths), 1)
        XCTAssertEqual(DirectoryBreadcrumbsView.treeIndex(of: "/Users", in: paths), -1)
        XCTAssertEqual(DirectoryBreadcrumbsView.treeIndex(of: "/", in: paths), -1)
        XCTAssertNil(DirectoryBreadcrumbsView.treeIndex(of: "/opt", in: paths))
        XCTAssertNil(DirectoryBreadcrumbsView.treeIndex(of: nil, in: paths))
    }

    /// Удержание: повторяются стрелки и ⌘←/⌘→; Enter, Space и буквы — по одному нажатию.
    func testOnlyArrowsRepeatWhenHeld() {
        for key in [KeyEquivalent.upArrow, .downArrow, .leftArrow, .rightArrow] {
            XCTAssertTrue(FolderTreeView.repeats(key, modifiers: []))
        }
        XCTAssertFalse(FolderTreeView.repeats(.return, modifiers: []))
        XCTAssertFalse(FolderTreeView.repeats(.space, modifiers: []))
        XCTAssertFalse(FolderTreeView.repeats(KeyEquivalent("a"), modifiers: []))
        XCTAssertTrue(FolderTreeView.repeats(.leftArrow, modifiers: .command), "⌘← бежит по пути")
        XCTAssertTrue(FolderTreeView.repeats(.rightArrow, modifiers: .command))
        XCTAssertFalse(FolderTreeView.repeats(.upArrow, modifiers: .command))
        XCTAssertFalse(FolderTreeView.repeats(.leftArrow, modifiers: .option), "⌥ больше не переключает")
    }
}
