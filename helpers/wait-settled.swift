// wait-settled — wait until a window is adopted AND geometrically still (v1).
//
// Usage: wait-settled <window_id> <display_id> <x> <y> <width> <height> [adopt_timeout_ms] [still_timeout_ms]
//
// Two phases in one process (one spawn per tick instead of separate
// wait-display + wait-rect spawns plus a Lua round-trip between them):
//
//   1. Adopt: poll `paneru query state` (25ms ticks, default 800ms) until the
//      window's display_id equals <display_id>. display_id flips are
//      discrete, so the first hit proceeds immediately.
//   2. Stillness: poll (40ms ticks, default 600ms) until the window's frame
//      center is inside [x, x+w) x [y, y+h) AND moved <2px across 3
//      consecutive reads. In-rect alone is not arrival — a window sliding
//      into its column spends most of its travel inside the display rect,
//      so a two-glance check fires mid-flight and any warp onto that frame
//      makes focus chase a moving window (in-place shake).
//
// Prints `settled at (X, Y)` from the same snapshot that proved stillness —
// callers warp to the printed point with no re-read (a re-read is a later
// snapshot; the window moved between them). Gives up early after 3
// consecutive motionless out-of-rect reads (a scroll that isn't happening
// shouldn't burn the budget).
//
// Exit 0 = settled (only then is stdout's point warp-safe); exit 1 =
// anything else — callers warp best-effort or proceed regardless, the
// printed line is the diagnostic.
//
// Used by the 2-display move path (adopt + target settle) and the restored
// source-viewport repair (neighbor stillness) in
// config/paneru/lib/displays.lua, which has no sleep primitive of its own.
//
// Needs no Accessibility grant: pure CLI + sleeps, no AXUIElement or
// synthetic CGEvent calls.
import CoreGraphics
import Foundation

let args = CommandLine.arguments
guard args.count >= 7 && args.count <= 9,
      let windowID = Int(args[1]),
      let targetDisplayID = Int(args[2]),
      let rx = Double(args[3]), let ry = Double(args[4]),
      let rw = Double(args[5]), let rh = Double(args[6]) else {
  FileHandle.standardError.write("usage: wait-settled <window_id> <display_id> <x> <y> <width> <height> [adopt_timeout_ms] [still_timeout_ms]\n".data(using: .utf8)!)
  exit(1)
}
var adoptTimeoutMs = 800.0
var stillTimeoutMs = 600.0
if args.count >= 8 {
  guard let t = Double(args[7]), t > 0 else {
    FileHandle.standardError.write("adopt_timeout_ms must be a positive number\n".data(using: .utf8)!)
    exit(1)
  }
  adoptTimeoutMs = t
}
if args.count >= 9 {
  guard let t = Double(args[8]), t > 0 else {
    FileHandle.standardError.write("still_timeout_ms must be a positive number\n".data(using: .utf8)!)
    exit(1)
  }
  stillTimeoutMs = t
}

func resolvePaneruBinary() -> String {
  for candidate in ["/opt/homebrew/bin/paneru", "/usr/local/bin/paneru"] {
    if FileManager.default.isExecutableFile(atPath: candidate) {
      return candidate
    }
  }
  return "paneru"
}

/// The window's (display_id, frame center) in one state dump, or nils when
/// the record/frame is missing. One spawn covers both — adoption and
/// stillness share the same reads.
func windowState(_ wid: Int) -> (display: Int?, center: CGPoint?) {
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
    return (nil, nil)
  }
  process.waitUntilExit()
  guard process.terminationStatus == 0,
        let data = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.data(using: .utf8),
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let workspaces = json["virtual_workspaces"] as? [[String: Any]] else {
    return (nil, nil)
  }
  for ws in workspaces {
    guard let windows = ws["windows"] as? [[String: Any]] else { continue }
    if let match = windows.first(where: { ($0["window_id"] as? Int) == wid }) {
      let did = match["display_id"] as? Int
      var center: CGPoint? = nil
      if let frame = match["frame"] as? [String: Any],
         let x = frame["x"] as? Double, let y = frame["y"] as? Double,
         let w = frame["width"] as? Double, let h = frame["height"] as? Double {
        center = CGPoint(x: x + w / 2, y: y + h / 2)
      }
      return (did, center)
    }
  }
  return (nil, nil)
}

func inside(_ p: CGPoint) -> Bool {
  p.x >= rx && p.x < rx + rw && p.y >= ry && p.y < ry + rh
}

func describe(_ p: CGPoint?) -> String {
  guard let p else { return "missing" }
  return "(\(Int(p.x)), \(Int(p.y)))"
}

func still(_ a: CGPoint, _ b: CGPoint) -> Bool {
  abs(a.x - b.x) < 2 && abs(a.y - b.y) < 2
}

// ─── Phase 1: adoption (discrete flip, first hit wins) ─────────────────────
let adoptQuantum: TimeInterval = 0.025
let adoptTicks = max(1, Int((adoptTimeoutMs / 1000.0 / adoptQuantum).rounded(.up)))
var lastDisplay: Int? = nil
var adopted = false
for i in 0..<adoptTicks {
  if i > 0 { Thread.sleep(forTimeInterval: adoptQuantum) }
  let (did, _) = windowState(windowID)
  guard let did else {
    print("wait-settled: window \(windowID) record missing")
    exit(1)
  }
  lastDisplay = did
  if did == targetDisplayID {
    adopted = true
    break
  }
}
guard adopted else {
  if let last = lastDisplay {
    print("wait-settled: window \(windowID) timeout waiting for display \(targetDisplayID) (at display \(last))")
  } else {
    print("wait-settled: window \(windowID) record missing")
  }
  exit(1)
}

// ─── Phase 2: stillness (in-rect AND unmoving, 3 consecutive reads) ─────────
let stillQuantum: TimeInterval = 0.04
let stillTicks = max(3, Int((stillTimeoutMs / 1000.0 / stillQuantum).rounded(.up)))
var prevIn: CGPoint? = nil
var consec = 0
var lastOut: CGPoint? = nil
var outStill = 0
var lastSeen: CGPoint? = nil
for i in 0..<stillTicks {
  if i > 0 { Thread.sleep(forTimeInterval: stillQuantum) }
  let (_, mc) = windowState(windowID)
  guard let c = mc else {
    print("wait-settled: window \(windowID) record missing")
    exit(1)
  }
  lastSeen = c
  if inside(c) {
    if let p = prevIn, still(p, c) {
      consec += 1
    } else {
      consec = 1
    }
    prevIn = c
    if consec >= 3 {
      print("wait-settled: window \(windowID) settled at \(describe(c))")
      exit(0)
    }
  } else {
    prevIn = nil
    consec = 0
    if let l = lastOut, still(l, c) {
      outStill += 1
    } else {
      outStill = 0
      lastOut = c
    }
    if outStill >= 3 {
      print("wait-settled: window \(windowID) static at \(describe(c)), outside [\(Int(rx)), \(Int(ry)), \(Int(rw))x\(Int(rh))] — viewport not following")
      exit(1)
    }
  }
}
print("wait-settled: window \(windowID) unsettled at \(describe(lastSeen))")
exit(1)
