import XCTest
@testable import Hatch

final class QuickActionTests: XCTestCase {
    private var folder: URL!

    private let safari = AppEntry(url: URL(fileURLWithPath: "/Applications/Safari.app"), bundleID: "com.apple.Safari",
                                  name: "Safari", localizedName: nil)
    private let mail = AppEntry(url: URL(fileURLWithPath: "/System/Applications/Mail.app"), bundleID: "com.apple.mail",
                                name: "Mail", localizedName: nil)
    private let calculator = AppEntry(url: URL(fileURLWithPath: "/System/Applications/Calculator.app"),
                                      bundleID: "com.apple.calculator", name: "Calculator", localizedName: "Калькулятор")
    private let vscode = AppEntry(url: URL(fileURLWithPath: "/Applications/Visual Studio Code.app"),
                                  bundleID: "com.microsoft.VSCode", name: "Visual Studio Code", localizedName: nil)

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("QuickActionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("src"), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: folder.appendingPathComponent("src/main.go").path, contents: Data())
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func resolver(exclusions: [String] = []) -> QuickActionResolver {
        QuickActionResolver(apps: [safari, mail, calculator, vscode], aliases: SettingsStore.defaultAppAliases,
                            exclusions: exclusions)
    }

    private func resolve(_ text: String, _ r: QuickActionResolver? = nil) -> QuickAction? {
        (r ?? resolver()).resolve(text, directory: folder.path)
    }

    func testExactNameOpensApp() {
        XCTAssertEqual(resolve("safari"), .openApp(safari))
        XCTAssertEqual(resolve("Safari "), .openApp(safari))
        XCTAssertEqual(resolve("калькулятор"), .openApp(calculator))
        XCTAssertEqual(resolve("visual studio code"), .openApp(vscode))
    }

    /// Совпадение с командой: побеждает приложение, пока имя не в исключениях.
    func testAppBeatsCommandUnlessExcluded() {
        XCTAssertEqual(resolve("mail"), .openApp(mail))
        XCTAssertNil(resolve("mail", resolver(exclusions: ["Mail"])))
    }

    func testAliases() {
        XCTAssertEqual(resolve("code"), .openApp(vscode))
        XCTAssertEqual(resolve("vscode"), .openApp(vscode))
    }

    func testNameWithPathsOpensThem() {
        let src = folder.appendingPathComponent("src").standardizedFileURL
        XCTAssertEqual(resolve("code ."), .openPaths(vscode, [folder.standardizedFileURL]))
        XCTAssertEqual(resolve("code src src/main.go"),
                       .openPaths(vscode, [src, src.appendingPathComponent("main.go")]))
        XCTAssertEqual(resolve("code \(folder.path)"), .openPaths(vscode, [folder.standardizedFileURL]))
    }

    /// Аргумент не путь — это команда: `mail -s …`, `code --version`.
    func testNonPathArgumentsStayCommands() {
        XCTAssertNil(resolve("mail -s hi"))
        XCTAssertNil(resolve("code --version"))
        XCTAssertNil(resolve("code . missing"))
        XCTAssertNil(resolve("docker ps"))
    }

    /// По началу имени — только подсказка: Enter её не выполняет.
    func testPrefixSuggestsOnly() {
        XCTAssertEqual(resolve("saf"), .suggestApp(safari, completion: "safari"))
        XCTAssertEqual(resolve("Saf"), .suggestApp(safari, completion: "Safari"))
        XCTAssertEqual(resolve("каль"), .suggestApp(calculator, completion: "калькулятор"))
        XCTAssertEqual(resolve("vs"), .suggestApp(vscode, completion: "vscode"))
        XCTAssertFalse(resolve("saf")!.handlesEnter)
        XCTAssertNil(resolve("s"))     // слишком коротко
        XCTAssertNil(resolve("saf "))  // после пробела — аргументы команды
        XCTAssertNil(resolve("ma", resolver(exclusions: ["mail"])))
    }

    func testCalculatorComesFirst() {
        XCTAssertEqual(resolve("2^10"), .calculate(1024))
        XCTAssertEqual(resolve("1/0"), .divisionByZero)
        XCTAssertNil(resolve("42"))
    }

    func testSwitchesOff() {
        var r = resolver()
        r.appsEnabled = false
        r.calculatorEnabled = false
        XCTAssertNil(resolve("safari", r))
        XCTAssertNil(resolve("saf", r))
        XCTAssertNil(resolve("2+2", r))
    }

    /// Папки на уровень вглубь (Utilities), локализованное имя, без дублей.
    func testCatalogScansOneLevelDeep() throws {
        let root = folder.appendingPathComponent("Apps")
        let fm = FileManager.default
        for path in ["Top.app", "Utilities/Deep.app", "Utilities/More/TooDeep.app", "NotAnApp"] {
            try fm.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        let names = AppCatalog.scan([root]).map(\.name)
        XCTAssertEqual(names, ["Deep", "Top"])
    }

    func testSettingsAliasesAndExclusions() {
        let defaults = UserDefaults(suiteName: "QuickActionTests.\(UUID().uuidString)")!
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.appAliases, ["vscode": "com.microsoft.VSCode", "code": "com.microsoft.VSCode"])
        XCTAssertTrue(store.openAppsFromInput)
        XCTAssertTrue(store.calculatorInInput)
        XCTAssertEqual(store.appExclusions, ["claude", "ollama", "opencode"])
        for name in ["claude", "ollama", "opencode"] { store.removeExclusion(name) }
        store.setAlias(" Term ", for: "com.apple.Terminal")
        store.setAlias("two words", for: "x")
        store.removeAlias("vscode")
        store.addExclusion("Claude")
        store.addExclusion("claude")
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.appAliases, ["code": "com.microsoft.VSCode", "term": "com.apple.Terminal"])
        XCTAssertEqual(reloaded.appExclusions, ["claude"])
        reloaded.removeExclusion("claude")
        XCTAssertEqual(reloaded.appExclusions, [])
    }
}
