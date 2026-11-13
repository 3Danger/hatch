import XCTest
@testable import Hatch

final class ListFilterTests: XCTestCase {
    func testRankOrder() {
        XCTAssertEqual(ListFilter.rank("pk", name: "pkpay"), .namePrefix)
        XCTAssertEqual(ListFilter.rank("base", name: "account-balance-base"), .wordPrefix)
        XCTAssertEqual(ListFilter.rank("ut", name: "MacUtils"), .wordPrefix)
        XCTAssertEqual(ListFilter.rank("ala", name: "account-balance-base"), .nameContains)
        XCTAssertEqual(ListFilter.rank("desk", name: "Debug", extra: "~/Desktop/HatchBuild"), .extraContains)
        XCTAssertNil(ListFilter.rank("zz", name: "pkpay", extra: "~/tmp"))
        XCTAssertEqual(ListFilter.rank("PK", name: "pkpay"), .namePrefix)
    }

    /// Набрано в русской раскладке — ищется как латиница; русские имена — как есть.
    func testRussianLayout() {
        XCTAssertEqual(ListFilter.latinLayout("зл"), "pk")
        XCTAssertEqual(ListFilter.latinLayout("еуд"), "tel")
        XCTAssertEqual(ListFilter.rank("зл", name: "pkpay"), .namePrefix)
        XCTAssertEqual(ListFilter.rank("заг", name: "Загрузки"), .namePrefix)
    }

    /// Совпадение в имени выше совпадения в пути; при равных — прежний порядок.
    func testFilterSortsByRank() {
        let items = [("Debug", "~/Desktop/Debug"), ("pkpay", "~/projects/pkpay"), ("Downloads", "~/Downloads"), ("app", "~/app")]
        let found = ListFilter.filter(items, query: "p", name: { $0.0 }, extra: { $0.1 })
        XCTAssertEqual(found.map(\.0), ["pkpay", "app", "Debug"])
        XCTAssertEqual(ListFilter.filter(items, query: "", name: { $0.0 }).count, 4)
    }

    func testAcceptedCharacters() {
        XCTAssertTrue(ListFilter.accepts("a", space: false))
        XCTAssertTrue(ListFilter.accepts("я", space: false))
        XCTAssertTrue(ListFilter.accepts("-", space: false))
        XCTAssertFalse(ListFilter.accepts(" ", space: false))
        XCTAssertTrue(ListFilter.accepts(" ", space: true))
        XCTAssertFalse(ListFilter.accepts("\u{1b}", space: true))
    }

    /// Несколько имён (Терминал и Terminal): начало любого имени выше середины другого.
    func testFilterByAnyName() {
        let apps = [["Заметки", "Notes"], ["Терминал", "Terminal"]]
        XCTAssertEqual(ListFilter.filter(apps, query: "еу", names: { $0 }).map(\.[0]), ["Терминал", "Заметки"])
        XCTAssertEqual(ListFilter.filter(apps, query: "тер", names: { $0 }).map(\.[0]), ["Терминал"])
    }
}
