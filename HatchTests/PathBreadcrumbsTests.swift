import XCTest
@testable import Hatch

final class PathBreadcrumbsTests: XCTestCase {

    func testHomeBasedPath() {
        let crumbs = PathBreadcrumbs.segments(for: "/Users/me/tmp/Hatch", home: "/Users/me")
        XCTAssertEqual(crumbs.map(\.title), ["~", "tmp", "Hatch"])
        XCTAssertEqual(crumbs.map(\.path), ["/Users/me", "/Users/me/tmp", "/Users/me/tmp/Hatch"])
    }

    func testHomeItself() {
        let crumbs = PathBreadcrumbs.segments(for: "/Users/me", home: "/Users/me")
        XCTAssertEqual(crumbs.map(\.title), ["~"])
    }

    func testOutsideHome() {
        let crumbs = PathBreadcrumbs.segments(for: "/usr/local/bin", home: "/Users/me")
        XCTAssertEqual(crumbs.map(\.title), ["/", "usr", "local", "bin"])
        XCTAssertEqual(crumbs.last?.path, "/usr/local/bin")
        XCTAssertEqual(crumbs.first?.path, "/")
    }

    /// Похожий префикс — не домашняя папка.
    func testSimilarPrefixIsNotHome() {
        let crumbs = PathBreadcrumbs.segments(for: "/Users/meow/x", home: "/Users/me")
        XCTAssertEqual(crumbs.first?.title, "/")
    }

    // MARK: - Папка в заголовке блока

    func testFolderName() {
        XCTAssertEqual(PathBreadcrumbs.folderName(for: "/Users/me/Downloads", home: "/Users/me"), "Downloads")
        XCTAssertEqual(PathBreadcrumbs.folderName(for: "/Users/me", home: "/Users/me"), "~")
        XCTAssertEqual(PathBreadcrumbs.folderName(for: "/", home: "/Users/me"), "/")
        XCTAssertEqual(PathBreadcrumbs.folderName(for: "/usr/local", home: "/Users/me"), "local")
    }

    func testDisplayPath() {
        XCTAssertEqual(PathBreadcrumbs.displayPath(for: "/Users/me/tmp/Hatch", home: "/Users/me"), "~/tmp/Hatch")
        XCTAssertEqual(PathBreadcrumbs.displayPath(for: "/Users/me", home: "/Users/me"), "~")
        XCTAssertEqual(PathBreadcrumbs.displayPath(for: "/usr/local", home: "/Users/me"), "/usr/local")
        XCTAssertEqual(PathBreadcrumbs.displayPath(for: "/", home: "/Users/me"), "/")
    }
}
