// wait-display — wait until a window reports a target display (v1).
//
// Usage: wait-display <window_id> <target_display_id> [timeout_ms]
//
// Polls `paneru query state` for the window's display_id to equal the target.
// The first read is immediate (the daemon may have applied the command
// already); subsequent ticks sleep 25ms so the wait spans real wall-clock
// time instead of exhausting in milliseconds. Default budget 800ms
// (32 ticks) covers the usual 100-300ms adoption lag with headroom; exits
// early on the first hit — display_id flips are discrete, so no stability
// rule is needed (unlike wait-rect's two-consecutive viewport check).
// Exit 0 = adopted; exit 1 = timeout/missing — callers proceed accordingly,
// the printed line is the diagnostic.
//
// Used by the 2-display move path in config/paneru/lib/displays.lua: Lua has
// no sleep primitive, so an in-dispatch busy poll of query_json can never
// observe a just-sent `window nextdisplay` command before it expires. One
// blocking helper spawn both yields the dispatch and spans real time — the
// same reason the 3+ adoption confirm lives inside move-display.
//
// Needs no Accessibility grant: pure CLI + sleeps, no AXUIElement or
// synthetic CGEvent calls.
import Foundation

let args = CommandLine.arguments
guard args.count == 3 || args.count == 4,
      let windowID = Int(args[1]),
      let targetDisplayID = Int(args[2]) else {
  FileHandle.standardError.write("usage: wait-display <window_id> <target_display_id> [timeout_ms]\n".data(using: .utf8)!)
  exit(1)
}
var timeoutMs = 800.0
if args.count == 4 {
  if let t = Double(args[3]), t > 0 {
    timeoutMs = t
  } else {
    FileHandle.standardError.write("timeout_ms must be a positive number\n".data(using: .utf8)!)
    exit(1)
  }
}

func resolvePaneruBinary() -> String {
  for candidate in ["/opt/homebrew/bin/paneru", "/usr/local/bin/paneru"] {
    if FileManager.default.isExecutableFile(atPath: candidate) {
      return candidate
    }
  }
  return "paneru"
}

func windowDisplay(_ wid: Int) -> Int? {
  let process = Process()
  if #available(macOS 10.13, *) {
    process.executableURL = URL(fileURLWithPath: resolvePaneruBinary())
  } else {
    process.launchPath = resolvePaneruBinary()
  }
  process.arguments = ["query", "state"]
  let outPipe = Pipe()
  process.standardOutput = outPipe
  process.standardError = FileHandle.nullDevice
  do {
    try process.run()
  } catch {
    return nil
  }
  process.waitUntilExit()
  guard process.terminationStatus == 0,
        let data = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.data(using: .utf8),
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let workspaces = json["virtual_workspaces"] as? [[String: Any]] else {
    return nil
  }
  for ws in workspaces {
    guard let windows = ws["windows"] as? [[String: Any]] else { continue }
    if let match = windows.first(where: { ($0["window_id"] as? Int) == wid }),
       let did = match["display_id"] as? Int {
      return did
    }
  }
  return nil
}

let quantum: TimeInterval = 0.025
let ticks = max(1, Int((timeoutMs / 1000.0 / quantum).rounded(.up)))
var lastSeen: Int? = nil
for i in 0..<ticks {
  if i > 0 { Thread.sleep(forTimeInterval: quantum) }
  guard let did = windowDisplay(windowID) else {
    print("wait-display: window \(windowID) record missing")
    exit(1)
  }
  lastSeen = did
  if did == targetDisplayID {
    print("wait-display: window \(windowID) adopted by display \(targetDisplayID) in \(i + 1) ticks")
    exit(0)
  }
}
if let last = lastSeen {
  print("wait-display: window \(windowID) timeout at display \(last), waiting for \(targetDisplayID)")
} else {
  print("wait-display: window \(windowID) record missing")
}
exit(1)
