import Foundation
import Testing
@testable import ClaudenotchiCore

@Suite struct HelperDeployerTests {
    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cn-deployer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeSource(_ dir: URL, contents: String = "#!/bin/sh\necho helper\n") throws -> URL {
        let url = dir.appendingPathComponent("source-helper")
        try Data(contents.utf8).write(to: url)
        return url
    }

    @Test func copiesTheHelperIntoPlaceAndMakesItExecutable() throws {
        let dir = try makeDirectory()
        let source = try makeSource(dir)
        let destination = dir.appendingPathComponent("bin/claudenotchi-hook")

        let changed = try HelperDeployer.deploy(source: source, destination: destination)

        #expect(changed)
        #expect(try Data(contentsOf: destination) == Data(contentsOf: source))
        let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
        #expect((attributes[.posixPermissions] as? Int) == 0o755)
    }

    @Test func leavesAnIdenticalHelperUntouched() throws {
        let dir = try makeDirectory()
        let source = try makeSource(dir)
        let destination = dir.appendingPathComponent("bin/claudenotchi-hook")
        try HelperDeployer.deploy(source: source, destination: destination)
        let before = try FileManager.default.attributesOfItem(atPath: destination.path)[.modificationDate] as? Date

        Thread.sleep(forTimeInterval: 0.05)
        let changed = try HelperDeployer.deploy(source: source, destination: destination)

        #expect(changed == false)
        #expect(try FileManager.default.attributesOfItem(atPath: destination.path)[.modificationDate] as? Date == before)
    }

    @Test func replacesAnOutdatedHelper() throws {
        let dir = try makeDirectory()
        let destination = dir.appendingPathComponent("bin/claudenotchi-hook")
        try HelperDeployer.deploy(source: try makeSource(dir, contents: "old"), destination: destination)

        let newer = dir.appendingPathComponent("newer")
        try Data("new version".utf8).write(to: newer)
        let changed = try HelperDeployer.deploy(source: newer, destination: destination)

        #expect(changed)
        #expect(try String(contentsOf: destination, encoding: .utf8) == "new version")
    }

    @Test func leavesNoTemporaryFilesBehind() throws {
        let dir = try makeDirectory()
        let source = try makeSource(dir)
        let destination = dir.appendingPathComponent("bin/claudenotchi-hook")
        try HelperDeployer.deploy(source: source, destination: destination)
        try HelperDeployer.deploy(source: try makeSource(dir, contents: "changed"), destination: destination)

        let names = try FileManager.default.contentsOfDirectory(atPath: destination.deletingLastPathComponent().path)
        #expect(names == ["claudenotchi-hook"])
    }

    @Test func failsClearlyWhenTheBundledHelperIsMissing() throws {
        let dir = try makeDirectory()
        #expect(throws: HelperDeployer.Failure.self) {
            try HelperDeployer.deploy(source: dir.appendingPathComponent("nope"), destination: dir.appendingPathComponent("bin/x"))
        }
    }

    @Test func theDefaultDestinationIsAStablePathInApplicationSupport() {
        #expect(HelperDeployer.defaultDestination().path.hasSuffix("/Library/Application Support/Claudenotchi/bin/claudenotchi-hook"))
    }
}
