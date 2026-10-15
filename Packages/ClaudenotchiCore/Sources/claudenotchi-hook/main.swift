import ClaudenotchiCore
import Foundation

// Claude Code runs this for each hook and pipes the hook JSON to stdin.
// Usage: claudenotchi-hook [--socket <path>]
//
// Always exits 0. Most hooks print nothing and return at once. For permission prompts it waits for
// the user's Approve/Deny in the app and prints Claude Code's decision JSON; if the app is not
// running or hangs up, it prints nothing and Claude Code shows its normal prompt.
var socketPath = SocketPath.default()
let arguments = CommandLine.arguments
if let flag = arguments.firstIndex(of: "--socket"), flag + 1 < arguments.count {
    socketPath = arguments[flag + 1]
}

let input = FileHandle.standardInput.readDataToEndOfFile()
let outcome = HookRunner.handle(stdin: input, socketPath: socketPath)
if let output = outcome.output {
    FileHandle.standardOutput.write(output)
}
exit(0)
