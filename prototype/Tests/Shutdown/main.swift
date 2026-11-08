import AppKit
let pid = Int32(CommandLine.arguments[1])!
guard let app = NSRunningApplication(processIdentifier: pid), app.terminate() else { exit(1) }
