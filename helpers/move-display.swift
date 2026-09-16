// move-display — teleport a window onto another display (v10, fast path).
//
// Paneru can only move a window to a single fixed display ("other().next()"
// in its ECS), which cannot reach every monitor on a 3+ display setup, and
// there is no "move to display N" primitive anywhere in paneru's protocol —
// checked the full Command/Operation/MouseMove vocabulary and the CLI argv
// grammar in the real paneru source (crates/shared_types/src/commands.rs,
// crates/shared_types/src/argv.rs): "nextdisplay"/"nextdisplaysend" are the
// only display-move tokens, both zero-argument. For 3+ display setups this
// helper does the physical relocation itself. It is invoked by
// config/paneru/lib/displays.lua (Cmd+Ctrl+Shift+arrows) and must be
// installed (compiled) at $HOME/.config/mac-scrolling-wm/helpers/move-display.
//
// Sequence:
//   1. Teleport via AX (set-position to a centered landing point + verify)
//   2. Warp pointer + synthetic mouseMoved so focus_follows_mouse and
//      paneru's ActiveDisplayMarker rotate to the target display (no click —
//      a real press/release causes press animations and can hit window
//      contents; warp-pointer uses the same mouseMoved mechanism)
//   3. Raise the moved window, settle it via a blocking `paneru window
//      fullwidth`, then poll `paneru query state` until the window reports
//      the target display (one raise + fullwidth retry on timeout). The
//      settle must be observed, not fire-and-forget: a detached launch
//      returns before the daemon applies it, so any caller-side adoption
//      check races and fails. Lua trusts this helper's exit code and pins
//      focus explicitly afterward.
//
// Performance notes (v10):
//   - No AppKit import: resolving/activating via NSRunningApplication pulled
//     AppKit init (~50-100ms) plus a 150ms unconditional activation sleep on
//     every run. Activation is now lazy: the first set-position is attempted
//     immediately, and only on failure is the window AX-raised with a short
//     30ms pause before retry.
//   - No pre-loop readFrame and no size re-reads: size is read once (to
//     compute a centered landing point), landing checks poll position only
//     (1 AX IPC instead of 2 per iteration).
//   - Corner teleport (display origin) is avoided: (tx, ty) sits under the
//     menu bar / in the notch area, so macOS clamps it and paneru then has to
//     animate a large correction. The window keeps its size and is placed so
//     its center lands at the target display's center (clamped on-screen),
//     minimizing the trailing settle animation.
//   - Retry loop is 4 attempts with ~5ms backoff only on a miss (was up to
//     10 attempts with 20ms sleeps plus 2 AX calls per pass).
//   - The trailing `paneru window fullwidth` blocks until applied and the
//     adoption poll confirms it (a detached launch let the caller's check
//     race and fail); the teleport path above keeps the keypress fast.
//
// Usage: move-display <window_id> <x> <y> <width> <height> <was_floating> <target_display_id>
// <window_id> is the exact CGWindowID Lua wants moved.
// <x> <y> <width> <height> is the target display's frame in CG coordinates.
// <was_floating> is accepted for CLI compatibility with displays.lua ("0"/"1")
// but currently ignored: both tiled and floating windows are teleported as-is
// and left for paneru to settle, per the Lua-side disposition handling.
// <target_display_id> is paneru's display id for the target display, used to
// confirm adoption via `paneru query state` before exiting 0.
//
// Exit 0 = success. Nonzero = failure (stderr has diagnostics).
//
// Needs Accessibility access granted to this specific compiled binary (a
// one-time macOS prompt) — see scripts/install-helpers for why this is built
// once with swiftc instead of run as an ephemeral `swift -e` script like the
// other helpers used to be: an ephemeral script gets a fresh, effectively
// anonymous identity on every run, which never keeps a TCC grant across
// invocations.
import ApplicationServices
import CoreGraphics
import Foundation

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

let args = CommandLine.arguments
guard args.count == 8, let windowIDArg = Int(args[1]),
      let windowID = UInt32(args[1]),
      let tx = Double(args[2]), let ty = Double(args[3]),
      let tw = Double(args[4]), let th = Double(args[5]),
      (args[6] == "0" || args[6] == "1"),
      let targetDisplayID = Int(args[7]) else {
  FileHandle.standardError.write(
    "usage: move-display <window_id> <x> <y> <width> <height> <was_floating(0|1)> <target_display_id>\n"
      .data(using: .utf8)!)
  exit(1)
}
// Accepted for CLI compatibility; teleport behavior is identical either way.
// (Tiled vs floating settle is owned by paneru / the Lua side.)
_ = args[6]

// ─── paneru CLI (blocking settle + adoption poll) ─────────────────────────

func resolvePaneruBinary() -> String {
  for candidate in ["/opt/homebrew/bin/paneru", "/usr/local/bin/paneru"] {
    if FileManager.default.isExecutableFile(atPath: candidate) {
      return candidate
    }
  }
  return "paneru"
}

/// Run `paneru <argv>` and wait for it, capturing output.
func runPaneruCLI(_ argv: [String]) -> (code: Int32, stdout: String, stderr: String) {
  let process = Process()
  if #available(macOS 10.13, *) {
    process.executableURL = URL(fileURLWithPath: resolvePaneruBinary())
  } else {
    process.launchPath = resolvePaneruBinary()
  }
  process.arguments = argv
  let outPipe = Pipe(), errPipe = Pipe()
  process.standardOutput = outPipe
  process.standardError = errPipe
  do {
    try process.run()
  } catch {
    return (-1, "", "failed to run paneru: \(error.localizedDescription)")
  }
  process.waitUntilExit()
  let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
  let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
  return (process.terminationStatus, out, err)
}

/// The window record for `wid` in `paneru query state`, or nil.
func findWindowState(_ wid: Int) -> [String: Any]? {
  let (_, stdout, _) = runPaneruCLI(["query", "state"])
  guard let data = stdout.data(using: .utf8),
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let workspaces = json["virtual_workspaces"] as? [[String: Any]] else {
    return nil
  }
  for ws in workspaces {
    guard let windows = ws["windows"] as? [[String: Any]] else { continue }
    if let match = windows.first(where: { ($0["window_id"] as? Int) == wid }) {
      return match
    }
  }
  return nil
}

/// Poll state until the window reports the target display, or time out.
/// Sleeps between ticks so the daemon has wall-clock time to apply the
/// settle — a sleep-less busy poll would exhaust before it lands.
func pollAdoption(retries: Int = 40, delay: TimeInterval = 0.05) -> Bool {
  for i in 0..<retries {
    if i > 0 { Thread.sleep(forTimeInterval: delay) }
    if let w = findWindowState(windowIDArg),
       (w["display_id"] as? Int) == targetDisplayID {
      return true
    }
  }
  return false
}

/// Settle via `window fullwidth` (blocking) and confirm adoption.
func settle() -> Bool {
  let (code, _, err) = runPaneruCLI(["send-cmd", "window", "fullwidth"])
  if code != 0 {
    FileHandle.standardError.write(
      "paneru window fullwidth failed: \(err)\n".data(using: .utf8)!)
    return false
  }
  return pollAdoption()
}

// ─── Resolve the AX window element ────────────────────────────────────────

func ownerPID(ofWindow wid: CGWindowID) -> pid_t? {
  guard let list = CGWindowListCopyWindowInfo(.optionIncludingWindow, wid) as? [[String: Any]],
        let info = list.first,
        let pid = info[kCGWindowOwnerPID as String] as? Int else {
    return nil
  }
  return pid_t(pid)
}

guard let pid = ownerPID(ofWindow: windowID) else {
  FileHandle.standardError.write("window \(windowID) not found\n".data(using: .utf8)!)
  exit(1)
}

let appElement = AXUIElementCreateApplication(pid)
var windowsRef: CFTypeRef?
guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
      let axWindows = windowsRef as? [AXUIElement] else {
  FileHandle.standardError.write("could not list windows for pid \(pid)\n".data(using: .utf8)!)
  exit(1)
}
var matchedWindow: AXUIElement?
for candidate in axWindows {
  var candidateID: CGWindowID = 0
  if _AXUIElementGetWindow(candidate, &candidateID) == .success, candidateID == windowID {
    matchedWindow = candidate
    break
  }
}
guard let window = matchedWindow else {
  FileHandle.standardError.write("window \(windowID) not found among pid \(pid)'s AX windows\n"
    .data(using: .utf8)!)
  exit(1)
}

// ─── Teleport via AX (centered landing, position-only verify) ─────────────

func readSize(_ window: AXUIElement) -> CGSize {
  var sizeRef: CFTypeRef?
  AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef)
  var size = CGSize.zero
  if let sizeRef { _ = AXValueGetValue((sizeRef as! AXValue), .cgSize, &size) }
  return size
}

func readPosition(_ window: AXUIElement) -> CGPoint {
  var positionRef: CFTypeRef?
  AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef)
  var position = CGPoint.zero
  if let positionRef { _ = AXValueGetValue((positionRef as! AXValue), .cgPoint, &position) }
  return position
}

func setPosition(_ window: AXUIElement, _ point: CGPoint) -> AXError {
  var p = point
  guard let value = AXValueCreate(.cgPoint, &p) else { return .failure }
  return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
}

func isOnTarget(center: CGPoint) -> Bool {
  center.x >= tx && center.x < tx + tw && center.y >= ty && center.y < ty + th
}

// Keep the window's size; land its center at the display's center, clamped
// so the frame stays on-screen when it fits. Top edge gets a small inset so
// we don't park under the menu bar (the old corner teleport hit exactly
// that clamping path on every run). If the window is bigger than the
// display, fall back to the display origin + inset.
let menuBarInset = 28.0
let winSize = readSize(window)
var landingOrigin: CGPoint
if winSize.width > 0 && winSize.height > 0 && winSize.width <= tw && winSize.height <= th {
  let cx = tx + (tw - winSize.width) / 2
  let cy = ty + menuBarInset + max(0, (th - menuBarInset - winSize.height) / 2)
  landingOrigin = CGPoint(x: cx, y: cy)
} else if winSize.width > 0 && winSize.height > 0 {
  landingOrigin = CGPoint(x: tx, y: ty + menuBarInset)
} else {
  // Size unreadable — still teleport; verify via position below.
  landingOrigin = CGPoint(x: tx + tw / 2, y: ty + th / 2)
}

let approxCenter = CGPoint(x: landingOrigin.x + winSize.width / 2,
                           y: landingOrigin.y + winSize.height / 2)

var landedCenter = approxCenter
var landed = false
var lastError: AXError = .success
for attempt in 0..<4 {
  if attempt > 0 {
    // Back off only between retries, never on the fast path.
    Thread.sleep(forTimeInterval: 0.005)
  }
  lastError = setPosition(window, landingOrigin)
  if lastError == .success {
    let pos = readPosition(window)
    // Position reads are synchronous with the set; derive the center from
    // the known size to avoid a second AX call per pass.
    let center: CGPoint
    if winSize.width > 0 && winSize.height > 0 {
      center = CGPoint(x: pos.x + winSize.width / 2, y: pos.y + winSize.height / 2)
    } else {
      center = pos
    }
    if isOnTarget(center: center) {
      landedCenter = center
      landed = true
      break
    }
    // Missed (clamped or still animating) — retry the same landing point.
    landedCenter = center
    continue
  }
  // The set itself failed. Some apps refuse repositioning while inactive:
  // raise via AX (same events paneru tracks focus with) and retry once
  // after a brief pause instead of paying an activation sleep every run.
  if attempt == 0 {
    AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    Thread.sleep(forTimeInterval: 0.03)
  }
}
guard landed else {
  if lastError != .success {
    FileHandle.standardError.write(
      "set position failed: \(lastError.rawValue)\n".data(using: .utf8)!)
  } else {
    FileHandle.standardError.write(
      "window \(windowID) did not land on target display: center (\(landedCenter.x), \(landedCenter.y)) not within [\(tx), \(tx + tw)) x [\(ty), \(ty + th))\n"
        .data(using: .utf8)!)
  }
  exit(1)
}

// ─── Warp + mouseMoved to rotate active display (no click) ────────────────

CGWarpMouseCursorPosition(landedCenter)
CGAssociateMouseAndMouseCursorPosition(1)
CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
        mouseCursorPosition: landedCenter, mouseButton: .left)?.post(tap: .cghidEventTap)

// ─── Raise, settle, and confirm adoption ──────────────────────────────────

// Raise the moved window before asking paneru to settle it, so the settle
// operates on (and leaves focus on) this window rather than a sibling the
// pointer may have hovered on the way over.
AXUIElementPerformAction(window, kAXRaiseAction as CFString)

if settle() { exit(0) }
// First settle missed — a focus race likely sent fullwidth at the wrong
// window. Raise again to restore macOS focus, wait briefly for paneru to
// track it, and settle once more before giving up.
FileHandle.standardError.write(
  "window \(windowID) not adopted by display \(targetDisplayID) after first settle; retrying\n"
    .data(using: .utf8)!)
AXUIElementPerformAction(window, kAXRaiseAction as CFString)
Thread.sleep(forTimeInterval: 0.1)
guard settle() else {
  FileHandle.standardError.write(
    "window \(windowID) did not settle on display \(targetDisplayID) after retry\n"
      .data(using: .utf8)!)
  exit(1)
}
