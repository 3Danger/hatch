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
}
