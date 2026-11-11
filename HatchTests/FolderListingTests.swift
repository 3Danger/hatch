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
}
