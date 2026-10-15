import Testing
@testable import ClaudenotchiCore

@Suite struct PathDisplayTests {
    @Test func replacesTheHomeDirectoryWithATilde() {
        #expect(PathDisplay.abbreviated("/Users/ana/Projects/app", home: "/Users/ana") == "~/Projects/app")
    }

    @Test func theHomeDirectoryItselfIsATilde() {
        #expect(PathDisplay.abbreviated("/Users/ana", home: "/Users/ana") == "~")
    }

    @Test func pathsOutsideHomeAreUnchanged() {
        #expect(PathDisplay.abbreviated("/tmp/work", home: "/Users/ana") == "/tmp/work")
    }

    @Test func aSiblingWithTheSamePrefixIsNotTreatedAsHome() {
        #expect(PathDisplay.abbreviated("/Users/anabel/app", home: "/Users/ana") == "/Users/anabel/app")
    }

    @Test func aTrailingSlashOnHomeStillMatches() {
        #expect(PathDisplay.abbreviated("/Users/ana/app", home: "/Users/ana/") == "~/app")
    }

    @Test func anEmptyHomeNeverMatches() {
        #expect(PathDisplay.abbreviated("/app", home: "") == "/app")
    }
}
