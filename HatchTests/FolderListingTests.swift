import XCTest
@testable import Hatch

final class FolderListingTests: XCTestCase {

    private func makeTree() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("folders-\(UUID().uuidString)", isDirectory: true)
        for name in ["beta", "Alpha", "gamma10", "gamma2", ".hidden"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        FileManager.default.createFile(atPath: root.appendingPathComponent("file.txt").path, contents: nil)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    /// Только папки, без скрытых, в порядке Finder (без учёта регистра, числа по значению).
    func testSubdirectoriesSortedLikeFinder() throws {
        let root = try makeTree()
        XCTAssertEqual(FolderListing.subdirectories(of: root.path), ["Alpha", "beta", "gamma2", "gamma10"])
    }

    func testHiddenOnRequest() throws {
        let root = try makeTree()
        XCTAssertTrue(FolderListing.subdirectories(of: root.path, includeHidden: true).contains(".hidden"))
    }

    /// Как в VS Code: любая часть пути — папки того же уровня, кликнутая выделена.
    /// У корня соседей нет — его вложенные папки.
    func testListingTargetIsAlwaysSiblings() {
        let crumbs = PathBreadcrumbs.segments(for: "/Users/me/tmp/Hatch", home: "/Users/me")
        XCTAssertEqual(FolderListing.target(for: crumbs[1]),
                       FolderListing.Target(directory: "/Users/me", highlighted: "tmp"))
        XCTAssertEqual(FolderListing.target(for: crumbs[2]),
                       FolderListing.Target(directory: "/Users/me/tmp", highlighted: "Hatch"))
        XCTAssertEqual(FolderListing.target(for: crumbs[0]),
                       FolderListing.Target(directory: "/Users", highlighted: "me"))

        let root = PathBreadcrumbs.segments(for: "/usr", home: "/Users/me")[0]
        XCTAssertEqual(FolderListing.target(for: root), FolderListing.Target(directory: "/", highlighted: nil))
    }
}
