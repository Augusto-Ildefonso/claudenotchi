import Foundation
import Testing
@testable import ClaudenotchiCore

@Suite struct HookInstallerTests {
    let helper = "/Users/ana/Library/Application Support/Claudenotchi/bin/claudenotchi-hook"
    let clock = Date(timeIntervalSince1970: 1_792_000_000) // 2026-10-14 ... fixed for backup names

    // MARK: helpers

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cn-installer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func installer(_ settings: URL, helperPath: String? = nil) -> HookInstaller {
        HookInstaller(settingsURL: settings, helperPath: helperPath ?? helper, now: { clock })
    }

    private func write(_ json: String, to url: URL) throws {
        try Data(json.utf8).write(to: url)
    }

    private func read(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func hooks(_ url: URL) throws -> [String: [[String: Any]]] {
        let root = try read(url)
        return (root["hooks"] as? [String: [[String: Any]]]) ?? [:]
    }

    /// Commands registered for one event, across all matcher groups.
    private func commands(_ url: URL, event: String) throws -> [String] {
        try hooks(url)[event, default: []].flatMap { group in
            (group["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String }
        }
    }

    private var ourCommand: String { "\"\(helper)\"" }

    // MARK: install

    @Test func installCreatesTheSettingsFileWhenMissing() throws {
        let dir = try makeDirectory()
        let settings = dir.appendingPathComponent("settings.json")
        let result = try installer(settings).install()

        #expect(result.changed)
        #expect(result.backupURL == nil) // nothing to back up
        for event in HookInstaller.events {
            #expect(try commands(settings, event: event) == [ourCommand], "\(event)")
        }
    }

    @Test func installCreatesMissingParentDirectories() throws {
        let dir = try makeDirectory()
        let settings = dir.appendingPathComponent("nested/.claude/settings.json")
        try installer(settings).install()
        #expect(FileManager.default.fileExists(atPath: settings.path))
    }

    @Test func installRegistersEveryClaudeCodeEventTheAppUses() {
        let expected: Set = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
                             "Notification", "PermissionRequest", "Stop", "SessionEnd"]
        #expect(Set(HookInstaller.events) == expected)
    }

    @Test func installKeepsEveryUnrelatedSetting() throws {
        let dir = try makeDirectory()
        let settings = dir.appendingPathComponent("settings.json")
        try write(#"{"model":"opus","permissions":{"allow":["Bash(ls:*)"]},"env":{"A":"1"}}"#, to: settings)
        try installer(settings).install()

        let root = try read(settings)
        #expect(root["model"] as? String == "opus")
        #expect((root["permissions"] as? [String: Any])?["allow"] as? [String] == ["Bash(ls:*)"])
        #expect((root["env"] as? [String: String]) == ["A": "1"])
    }

    @Test func installKeepsTheUsersOwnHooksOnTheSameEvents() throws {
        let dir = try makeDirectory()
        let settings = dir.appendingPathComponent("settings.json")
        try write(#"""
        {"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"/usr/local/bin/audit"}]}],
                  "UserPromptSubmit":[{"hooks":[{"type":"command","command":"echo hi"}]}]}}
        """#, to: settings)
        try installer(settings).install()

        #expect(try commands(settings, event: "PreToolUse").sorted() == ["/usr/local/bin/audit", ourCommand].sorted())
        #expect(try commands(settings, event: "UserPromptSubmit").contains("echo hi"))
        let preToolUse = try hooks(settings)["PreToolUse"] ?? []
        #expect(preToolUse.contains { ($0["matcher"] as? String) == "Bash" }, "the user's matcher survives")
    }

    @Test func installingTwiceDoesNotDuplicate() throws {
        let dir = try makeDirectory()
        let settings = dir.appendingPathComponent("settings.json")
        try installer(settings).install()
        let second = try installer(settings).install()

        #expect(second.changed == false)
        #expect(second.backupURL == nil)
        for event in HookInstaller.events {
            #expect(try commands(settings, event: event).count == 1, "\(event)")
        }
    }

    @Test func installingAgainWithANewHelperPathReplacesTheOldEntry() throws {
        let dir = try makeDirectory()
        let settings = dir.appendingPathComponent("settings.json")
        try installer(settings, helperPath: "/old/place/claudenotchi-hook").install()
        try installer(settings, helperPath: "/new place/claudenotchi-hook").install()

        #expect(try commands(settings, event: "Stop") == ["\"/new place/claudenotchi-hook\""])
    }

    @Test func installBacksUpTheExistingFileFirst() throws {
        let dir = try makeDirectory()
        let settings = dir.appendingPathComponent("settings.json")
        let original = #"{"model":"opus"}"#
        try write(original, to: settings)
        let result = try installer(settings).install()

        let backup = try #require(result.backupURL)
        #expect(backup.deletingLastPathComponent() == settings.deletingLastPathComponent())
        #expect(backup.lastPathComponent.hasPrefix("settings.json.claudenotchi-backup-"))
        #expect(try String(contentsOf: backup, encoding: .utf8) == original)
    }

    @Test func backupsNeverOverwriteEachOther() throws {
        let dir = try makeDirectory()
        let settings = dir.appendingPathComponent("settings.json")
        try write(#"{"a":1}"#, to: settings)
        let first = try #require(try installer(settings).install().backupURL)
        try write(#"{"a":2}"#, to: settings) // changed again behind our back
        let second = try #require(try installer(settings).install().backupURL)

        #expect(first != second)
        #expect(try String(contentsOf: first, encoding: .utf8) == #"{"a":1}"#)
        #expect(try String(contentsOf: second, encoding: .utf8) == #"{"a":2}"#)
    }

    @Test func installRefusesInvalidJSONAndLeavesTheFileAlone() throws {
        let dir = try makeDirectory()
        let settings = dir.appendingPathComponent("settings.json")
        let broken = #"{"model": "opus""#  // truncated
        try write(broken, to: settings)

        #expect(throws: HookInstaller.Failure.self) { try installer(settings).install() }
        #expect(try String(contentsOf: settings, encoding: .utf8) == broken)
        let siblings = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(siblings == ["settings.json"], "no backup or temp file left behind")
    }

    @Test func installRefusesAFileWithCommentsInsteadOfStrippingThem() throws {
        let dir = try makeDirectory()
        let settings = dir.appendingPathComponent("settings.json")
        let commented = "{\n  // my notes\n  \"model\": \"opus\"\n}\n"
        try write(commented, to: settings)

        #expect(throws: HookInstaller.Failure.self) { try installer(settings).install() }
        #expect(throws: HookInstaller.Failure.self) { try installer(settings).uninstall() }
        #expect(try String(contentsOf: settings, encoding: .utf8) == commented)
    }

    @Test func installRefusesAFileThatIsNotAJSONObject() throws {
        let dir = try makeDirectory()
        let settings = dir.appendingPathComponent("settings.json")
        try write("[1,2,3]", to: settings)
        #expect(throws: HookInstaller.Failure.self) { try installer(settings).install() }
    }

    @Test func installRefusesUnexpectedHookStructureInsteadOfClobberingIt() throws {
        let dir = try makeDirectory()
        let settings = dir.appendingPathComponent("settings.json")
        let odd = #"{"hooks":{"Stop":"not an array"}}"#
        try write(odd, to: settings)
        #expect(throws: HookInstaller.Failure.self) { try installer(settings).install() }
        #expect(try String(contentsOf: settings, encoding: .utf8) == odd)
    }

    @Test func installWritesThroughASymlinkedSettingsFile() throws {
        let dir = try makeDirectory()
        let real = dir.appendingPathComponent("dotfiles-settings.json")
        let link = dir.appendingPathComponent("settings.json")
        try write(#"{"model":"opus"}"#, to: real)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        try installer(link).install()

        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) == real.path, "still a symlink")
        #expect(try commands(real, event: "Stop") == [ourCommand])
        #expect(try read(real)["model"] as? String == "opus")
    }

    @Test func installedCommandWorksWithSpacesInThePath() throws {
        let dir = try makeDirectory()
        let settings = dir.appendingPathComponent("settings.json")
        try installer(settings).install()
        #expect(try commands(settings, event: "PreToolUse") == ["\"\(helper)\""])
    }

    // MARK: uninstall

    @Test func uninstallRemovesOnlyOurEntries() throws {
        let dir = try makeDirectory()
        let settings = dir.appendingPathComponent("settings.json")
        try write(#"{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"/usr/local/bin/audit"}]}]}}"#, to: settings)
        try installer(settings).install()
        try installer(settings).uninstall()

        #expect(try commands(settings, event: "PreToolUse") == ["/usr/local/bin/audit"])
        #expect(try hooks(settings).keys.sorted() == ["PreToolUse"])
    }

    @Test func installThenUninstallRestoresAFileThatHadNoHooks() throws {
        let dir = try makeDirectory()
        let settings = dir.appendingPathComponent("settings.json")
        try write(#"{"model":"opus","env":{"A":"1"}}"#, to: settings)
        let before = try read(settings) as NSDictionary
        try installer(settings).install()
        try installer(settings).uninstall()
        #expect((try read(settings) as NSDictionary) == before)
    }

    @Test func uninstallRemovesAnEntryEvenIfOurHelperMovedSinceInstall() throws {
        let dir = try makeDirectory()
        let settings = dir.appendingPathComponent("settings.json")
        try installer(settings, helperPath: "/somewhere/else/claudenotchi-hook").install()
        try installer(settings).uninstall() // a different helper path than the one installed
        #expect(try hooks(settings).isEmpty)
    }

    @Test func uninstallBacksUpBeforeChanging() throws {
        let dir = try makeDirectory()
        let settings = dir.appendingPathComponent("settings.json")
        try installer(settings).install()
        let result = try installer(settings).uninstall()
        #expect(result.changed)
        #expect(result.backupURL != nil)
    }

    @Test func uninstallWithNothingToRemoveDoesNothing() throws {
        let dir = try makeDirectory()
        let settings = dir.appendingPathComponent("settings.json")
        try write(#"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo bye"}]}]}}"#, to: settings)
        let result = try installer(settings).uninstall()
        #expect(result == HookInstaller.Result(changed: false, backupURL: nil))
        #expect(try commands(settings, event: "Stop") == ["echo bye"])
    }

    @Test func uninstallWithoutASettingsFileIsANoOp() throws {
        let dir = try makeDirectory()
        let settings = dir.appendingPathComponent("settings.json")
        let result = try installer(settings).uninstall()
        #expect(result.changed == false)
        #expect(!FileManager.default.fileExists(atPath: settings.path))
    }

    @Test func uninstallOnlyRecognizesTheRealHelperName() throws {
        let dir = try makeDirectory()
        let settings = dir.appendingPathComponent("settings.json")
        try write(#"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"/usr/bin/tool --note claudenotchi-hook"},{"type":"command","command":"/x/not-claudenotchi-hook"}]}]}}"#, to: settings)
        try installer(settings).uninstall()
        #expect(try commands(settings, event: "Stop").count == 2)
    }

    // MARK: isInstalled

    @Test func isInstalledFollowsInstallAndUninstall() throws {
        let dir = try makeDirectory()
        let settings = dir.appendingPathComponent("settings.json")
        let sut = installer(settings)
        #expect(try sut.isInstalled() == false) // no file
        try sut.install()
        #expect(try sut.isInstalled())
        try sut.uninstall()
        #expect(try sut.isInstalled() == false)
    }

    @Test func isInstalledIsFalseWhenAnEventIsMissing() throws {
        let dir = try makeDirectory()
        let settings = dir.appendingPathComponent("settings.json")
        let sut = installer(settings)
        try sut.install()
        var root = try read(settings)
        var all = root["hooks"] as! [String: Any]
        all.removeValue(forKey: "Stop")
        root["hooks"] = all
        try JSONSerialization.data(withJSONObject: root).write(to: settings)
        #expect(try sut.isInstalled() == false)
    }

    @Test func isInstalledIsFalseWhenThePathPointsSomewhereElse() throws {
        let dir = try makeDirectory()
        let settings = dir.appendingPathComponent("settings.json")
        try installer(settings, helperPath: "/old/claudenotchi-hook").install()
        #expect(try installer(settings).isInstalled() == false)
    }
}
