import ClaudenotchiCore
import Foundation

// Claude Code runs this for each hook and pipes the hook JSON to stdin.
// Usage: claudenotchi-hook [--socket <path>]
// Always exits 0 and prints nothing, so it can never block or disturb a session.
var socketPath = SocketPath.default()
let arguments = CommandLine.arguments
if let flag = arguments.firstIndex(of: "--socket"), flag + 1 < arguments.count {
    socketPath = arguments[flag + 1]
}

let input = FileHandle.standardInput.readDataToEndOfFile()
HookRunner.run(stdin: input, socketPath: socketPath)
exit(0)
