import XCTest
@testable import Hatch

final class CommandNotFoundTests: XCTestCase {
    func testFirstWordSkipsAssignments() {
        XCTAssertEqual(CommandNotFound.firstWord("gti status"), "gti")
        XCTAssertEqual(CommandNotFound.firstWord("FOO=1 BAR=x gti"), "gti")
        XCTAssertNil(CommandNotFound.firstWord("   "))
    }

    func testMissingOnlyWhenFirstWordNotFound() {
        XCTAssertTrue(CommandNotFound.isMissing(command: "gti status", exitCode: 127, output: "zsh: command not found: gti"))
        XCTAssertTrue(CommandNotFound.isMissing(command: "gti", exitCode: 127, output: "bash: gti: command not found"))
        XCTAssertTrue(CommandNotFound.isMissing(command: "./buidl.sh", exitCode: 127,
                                                output: "zsh: no such file or directory: ./buidl.sh"))
        // не нашлась команда внутри скрипта — блок остаётся
        XCTAssertFalse(CommandNotFound.isMissing(command: "./build.sh", exitCode: 127, output: "./build.sh: line 3: foo: command not found"))
        XCTAssertFalse(CommandNotFound.isMissing(command: "gti", exitCode: 1, output: "zsh: command not found: gti"))
        XCTAssertFalse(CommandNotFound.isMissing(command: "gti", exitCode: nil, output: "zsh: command not found: gti"))
    }

    func testSuggestions() {
        let commands = ["git", "gtimeout", "grep", "ls", "tee", "test"]
        let apps = ["Telegram", "Terminal", "TextEdit", "Safari"]
        XCTAssertEqual(CommandNotFound.suggestions(for: "gti", commands: commands, apps: apps).first, "git")
        XCTAssertEqual(CommandNotFound.suggestions(for: "sfari", commands: commands, apps: apps), ["Safari"])
        XCTAssertEqual(CommandNotFound.suggestions(for: "te", commands: commands, apps: apps + ["TV"]),
                       ["Telegram", "Terminal", "TextEdit"])
        XCTAssertEqual(CommandNotFound.suggestions(for: "zzzzqq", commands: commands, apps: apps), [])
    }

    func testEditDistanceCountsTransposition() {
        XCTAssertEqual(CommandNotFound.editDistance("gti", "git"), 1)
        XCTAssertEqual(CommandNotFound.editDistance("kitten", "sitting"), 3)
    }

    func testReplacingFirstWord() {
        XCTAssertEqual(CommandNotFound.replacingFirstWord(in: "gti status -s", with: "git"), "git status -s")
        XCTAssertEqual(CommandNotFound.replacingFirstWord(in: "te", with: "Telegram"), "Telegram")
    }
}
