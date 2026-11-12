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

    /// Буквы: по началу имени со следующей строки; повтор листает; от двух букв — вразбивку; пауза сбрасывает.
    func testTypeAhead() {
        var tree = FolderTree(crumb: "/Users/me/git/hatch")
        let t0 = Date(timeIntervalSince1970: 1000)
        tree.handle(.character("k"), children: children, now: t0)
        XCTAssertEqual(tree.focus, "/Users/me/git/kafka-tools")
        tree.handle(.character("t"), children: children, now: t0.addingTimeInterval(0.3)) // «kt» — вразбивку
        XCTAssertEqual(tree.focus, "/Users/me/git/kafka-tools")
        XCTAssertEqual(tree.typed, "kt")
        tree.handle(.character("g"), children: children, now: t0.addingTimeInterval(2)) // после паузы — заново
        XCTAssertEqual(tree.typed, "g")
        XCTAssertEqual(tree.focus, "/Users/me/git/go-wallets")
        tree.handle(.down, children: children)
        XCTAssertEqual(tree.typed, "", "другая клавиша сбрасывает набор")
    }

    func testSingleLetterDoesNotMatchInsideName() {
        var tree = FolderTree(crumb: "/Users/me/git/hatch")
        tree.handle(.character("w"), children: children) // «go-wallets» начинается не с w
        XCTAssertEqual(tree.focus, "/Users/me/git/hatch")
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

    /// Удержание: повторяются стрелки и ⌥←/⌥→; Enter, Space и буквы — по одному нажатию.
    func testOnlyArrowsRepeatWhenHeld() {
        for key in [KeyEquivalent.upArrow, .downArrow, .leftArrow, .rightArrow] {
            XCTAssertTrue(FolderTreeView.repeats(key, modifiers: []))
        }
        XCTAssertFalse(FolderTreeView.repeats(.return, modifiers: []))
        XCTAssertFalse(FolderTreeView.repeats(.space, modifiers: []))
        XCTAssertFalse(FolderTreeView.repeats(KeyEquivalent("a"), modifiers: []))
        XCTAssertTrue(FolderTreeView.repeats(.leftArrow, modifiers: .option), "⌥← бежит по пути")
        XCTAssertTrue(FolderTreeView.repeats(.rightArrow, modifiers: .option))
        XCTAssertFalse(FolderTreeView.repeats(.upArrow, modifiers: .option))
    }
}
