// wait-rect — wait until a window's frame center is inside a rect (v1).
//
// Usage: wait-rect <window_id> <x> <y> <width> <height>
//
// Polls `paneru query state` (up to 8 ticks, 75ms apart) for the window's
// frame center to lie within [x, x+w) x [y, y+h), requiring two consecutive
// in-rect reads (stability, not a glance — viewport scrolls animate). Gives
// up early after 3 consecutive motionless out-of-rect reads (a scroll that
// isn't happening shouldn't burn the budget). Exit 0 = centered; exit 1 =
// anything else — callers proceed regardless, the printed line is the
// diagnostic (final geometry on timeout, so a stuck viewport is provable
// instead of silent).
//
// Used by the 2-display move path in config/paneru/lib/displays.lua, which
// has no sleep primitive of its own: Lua busy-polling would spin CPU
// waiting out wall-clock animations.
//
// Needs no Accessibility grant: pure CLI + sleeps, no AXUIElement or
// synthetic CGEvent calls — which is also why this is a separate binary
// instead of logic inside move-display (that helper's warp needs TCC;
// this one must install grant-free).
import CoreGraphics
import Foundation

let args = CommandLine.arguments
guard args.count == 6, let windowID = Int(args[1]),
      let rx = Double(args[2]), let ry = Double(args[3]),
      let rw = Double(args[4]), let rh = Double(args[5]) else {
  FileHandle.standardError.write("usage: wait-rect <window_id> <x> <y> <width> <height>\n".data(using: .utf8)!)
  exit(1)
}

func resolvePaneruBinary() -> String {
  for candidate in ["/opt/homebrew/bin/paneru", "/usr/local/bin/paneru"] {
    if FileManager.default.isExecutableFile(atPath: candidate) {
      return candidate
    }
  }
  return "paneru"
}

func windowCenter(_ wid: Int) -> CGPoint? {
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
       let frame = match["frame"] as? [String: Any],
       let x = frame["x"] as? Double, let y = frame["y"] as? Double,
       let w = frame["width"] as? Double, let h = frame["height"] as? Double {
      return CGPoint(x: x + w / 2, y: y + h / 2)
    }
  }
  return nil
}

func inside(_ p: CGPoint) -> Bool {
  p.x >= rx && p.x < rx + rw && p.y >= ry && p.y < ry + rh
}

func describe(_ p: CGPoint?) -> String {
  guard let p else { return "missing" }
  return "(\(Int(p.x)), \(Int(p.y)))"
}

var prevInside = false
var last: CGPoint? = nil
var still = 0
var lastSeen: CGPoint? = nil
for i in 0..<8 {
  if i > 0 { Thread.sleep(forTimeInterval: 0.075) }
  guard let c = windowCenter(windowID) else {
    print("wait-rect: window \(windowID) record missing")
    exit(1)
  }
  lastSeen = c
  if inside(c) {
    if prevInside {
      print("wait-rect: window \(windowID) centered at \(describe(c))")
      exit(0)
    }
    prevInside = true
  } else {
    prevInside = false
    if let l = last, abs(l.x - c.x) < 0.5 && abs(l.y - c.y) < 0.5 {
      still += 1
    } else {
      still = 0
      last = c
    }
    if still >= 3 {
      print("wait-rect: window \(windowID) static at \(describe(c)), outside [\(Int(rx)), \(Int(ry)), \(Int(rw))x\(Int(rh))] — viewport not following")
      exit(1)
    }
  }
}
print("wait-rect: window \(windowID) timeout at \(describe(lastSeen)), outside [\(Int(rx)), \(Int(ry)), \(Int(rw))x\(Int(rh))]")
exit(1)
