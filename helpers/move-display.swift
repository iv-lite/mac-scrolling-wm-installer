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
//   4. Center the source neighbor on a background thread (.userInitiated)
//      while the main thread polls adoption: the poll reads display_id
//      (focus-independent) while centering changes focus (doesn't affect
//      display_id) — no shared state, so total time is max(poll, bg), never
//      more than sequential. Joined before the retry decision, so the retry
//      path stays single-threaded. Centering focuses the neighbor, verifies
//      the focus id, then waits for the GEOMETRIC effect — the neighbor
//      observed inside the source rect, stable across two reads — because
//      focus alone never proved the viewport scroll completed (an immediate
//      refocus supersedes the animation). Bounded (~8x75ms) with early
//      abort on a static frame; skipped up front when already consistent,
//      and never fails the move — centering is polish.
//   5. Re-warp to the window's live center (fullwidth resizes it after the
//      step-2 warp) and report total elapsed ms on stderr — the only timing
//      signal for the move path, so sluggishness is measurable.
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
//   - Oversized windows are shrunk to fit the target display before
//     teleporting (best-effort AX size-set, verified by re-read): paneru
//     won't adopt a window spilling far past the display edges, and the
//     smaller frame also shortens the animated correction. fullwidth still
//     sets the final size, so the shrink is invisible in the end state.
//   - Retry loop is 4 attempts with ~5ms backoff only on a miss (was up to
//     10 attempts with 20ms sleeps plus 2 AX calls per pass).
//   - The trailing `paneru window fullwidth` blocks until applied and the
//     adoption poll confirms it (a detached launch let the caller's check
//     race and fail); the poll is short (10 x 50ms + one retry) because
//     fullwidth already applied — a sleep-less or minute-long poll would
//     either race or freeze the keypress. Source centering overlaps the
//     poll on a background thread (disjoint state, see step 4) instead of
//     extending the tail. The paneru binary path resolves once, not twice
//     per CLI spawn (~15 spawns per move).
//
// Usage: move-display <window_id> <x> <y> <width> <height> <was_floating> <target_display_id> <center_side> <center_window_id>
// <window_id> is the exact CGWindowID Lua wants moved.
// <x> <y> <width> <height> is the target display's frame in CG coordinates.
// <was_floating> is accepted for CLI compatibility with displays.lua ("0"/"1")
// but currently ignored: both tiled and floating windows are teleported as-is
// and left for paneru to settle, per the Lua-side disposition handling.
// <target_display_id> is paneru's display id for the target display, used to
// confirm adoption via `paneru query state` before exiting 0.
// <center_side> ("east"/"west"/"none") and <center_window_id> select the
// neighboring column to center on the source display after adoption (see
// step 4); anything else skips centering.
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
import Dispatch
import Foundation

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

let args = CommandLine.arguments
guard args.count == 10, let windowIDArg = Int(args[1]),
      let windowID = UInt32(args[1]),
      let tx = Double(args[2]), let ty = Double(args[3]),
      let tw = Double(args[4]), let th = Double(args[5]),
      (args[6] == "0" || args[6] == "1"),
      let targetDisplayID = Int(args[7]),
      let centerWindowID = Int(args[9]) else {
  FileHandle.standardError.write(
    "usage: move-display <window_id> <x> <y> <width> <height> <was_floating(0|1)> <target_display_id> <center_side> <center_window_id>\n"
      .data(using: .utf8)!)
  exit(1)
}
let wasFloating = args[6] == "1"
// Which neighboring column to center on the source display ("east"/"west"),
// resolved by Lua; anything else (e.g. "none") skips centering.
let centerSide = args[8]

let startTime = Date()

/// Total elapsed ms since launch, reported on stderr before successful exit
/// so moves stay measurable from the Lua log alone.
func reportElapsed() {
  let ms = Int(Date().timeIntervalSince(startTime) * 1000)
  FileHandle.standardError.write("elapsed=\(ms)ms\n".data(using: .utf8)!)
}

// ─── paneru CLI (blocking settle + adoption poll) ─────────────────────────

/// Resolved once: the per-spawn filesystem probe it replaces ran twice per
/// CLI invocation (~15 spawns per move).
let PANERU_BIN: String = {
  for candidate in ["/opt/homebrew/bin/paneru", "/usr/local/bin/paneru"] {
    if FileManager.default.isExecutableFile(atPath: candidate) {
      return candidate
    }
  }
  return "paneru"
}()

@Sendable
func resolvePaneruBinary() -> String {
  PANERU_BIN
}

/// Run `paneru <argv>` and wait for it, capturing output.
@Sendable
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
@Sendable
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
/// settle — a sleep-less busy poll would exhaust before it lands. Kept
/// short on purpose: fullwidth above already applied, so adoption should
/// be near-immediate; lingering here is what freezes the keypress.
func pollAdoption(retries: Int = 10, delay: TimeInterval = 0.05) -> Bool {
  for i in 0..<retries {
    if i > 0 { Thread.sleep(forTimeInterval: delay) }
    if let w = findWindowState(windowIDArg),
       (w["display_id"] as? Int) == targetDisplayID {
      return true
    }
  }
  return false
}

/// Run `window fullwidth` (blocking) without polling. Split out of settle
/// so the first attempt's fullwidth can overlap the centering thread below.
func runFullwidth() -> Bool {
  let (code, _, err) = runPaneruCLI(["send-cmd", "window", "fullwidth"])
  if code != 0 {
    FileHandle.standardError.write(
      "paneru window fullwidth failed: \(err)\n".data(using: .utf8)!)
    return false
  }
  return true
}

/// Settle via `window fullwidth` (blocking) and confirm adoption. Used by
/// the retry path, which stays single-threaded.
func settle() -> Bool {
  guard runFullwidth() else { return false }
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

func setSize(_ window: AXUIElement, _ size: CGSize) -> AXError {
  var s = size
  guard let value = AXValueCreate(.cgSize, &s) else { return .failure }
  return AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
}

func isOnTarget(center: CGPoint) -> Bool {
  center.x >= tx && center.x < tx + tw && center.y >= ty && center.y < ty + th
}

let menuBarInset = 28.0
var winSize = readSize(window)
// Shrink oversized windows to fit the target display before teleporting:
// paneru won't adopt a window spilling far past the display edges (seen
// live: sub-display windows adopt on the builtin, oversized ones never
// do). Best-effort — apps that resist keep their size and take the old
// path below. fullwidth still sets the final size, so a successful shrink
// is invisible in the end state (and shortens the animated correction).
if winSize.width > tw || winSize.height > th - menuBarInset {
  let fit = CGSize(width: min(max(winSize.width, 0), tw),
                   height: min(max(winSize.height, 0), th - menuBarInset))
  if fit.width > 0 && fit.height > 0,
     setSize(window, fit) == .success {
    winSize = readSize(window)
  }
}

// Land at the display's center, clamped so the frame stays on-screen when
// it fits. Top edge gets a small inset so we don't park under the menu bar
// (the old corner teleport hit exactly that clamping path on every run).
// If the window is bigger than the display, fall back to the display
// origin + inset.
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

func warpTo(_ point: CGPoint) {
  CGWarpMouseCursorPosition(point)
  CGAssociateMouseAndMouseCursorPosition(1)
  CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
          mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
}

warpTo(landedCenter)

// ─── Raise, settle, and confirm adoption ──────────────────────────────────

// Raise the moved window before asking paneru to settle it, so the settle
// operates on (and leaves focus on) this window rather than a sibling the
// pointer may have hovered on the way over.
AXUIElementPerformAction(window, kAXRaiseAction as CFString)

/// Focused window id from `paneru query active`, or nil. Small payload by
/// design — cheaper than a full state dump for a single id check.
@Sendable
func queryFocusedWindowID() -> Int? {
  let (code, stdout, _) = runPaneruCLI(["query", "active"])
  guard code == 0,
        let data = stdout.data(using: .utf8),
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let active = json["active"] as? [String: Any],
        let fid = active["focused_window_id"] as? Int else {
    return nil
  }
  return fid
}

/// Online displays, resolved once per process. Same CG space the geometry
/// helper reports to Lua, so rects line up with state frames.
let ALL_DISPLAYS: [(id: Int, rect: CGRect)] = {
  var count: UInt32 = 0
  CGGetOnlineDisplayList(0, nil, &count)
  var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
  CGGetOnlineDisplayList(count, &ids, &count)
  return ids.map { (id: Int($0), rect: CGDisplayBounds($0)) }
}()

/// The display rect containing the point (geometric match — no id-space
/// assumption), or nil when off every display.
@Sendable
func displayContaining(_ p: CGPoint) -> CGRect? {
  ALL_DISPLAYS.first(where: { $0.rect.contains(p) })?.rect
}

/// Frame center from a state window record, or nil when missing/malformed.
@Sendable
func recordCenter(_ w: [String: Any]) -> CGPoint? {
  guard let frame = w["frame"] as? [String: Any],
        let x = frame["x"] as? Double, let y = frame["y"] as? Double,
        let fw = frame["width"] as? Double, let fh = frame["height"] as? Double else {
    return nil
  }
  return CGPoint(x: x + fw / 2, y: y + fh / 2)
}

/// Live center of the centering-target neighbor, or nil.
@Sendable
func neighborCenter() -> CGPoint? {
  guard let w = findWindowState(centerWindowID) else { return nil }
  return recordCenter(w)
}

@Sendable
func inside(_ p: CGPoint, _ r: CGRect) -> Bool {
  p.x >= r.origin.x && p.x < r.origin.x + r.width &&
  p.y >= r.origin.y && p.y < r.origin.y + r.height
}

@Sendable
func describe(_ p: CGPoint?) -> String {
  guard let p else { return "missing" }
  return "(\(Int(p.x)), \(Int(p.y)))"
}

/// Center the source neighbor after adoption is confirmed. Runs the focus
/// CLI, verifies focus landed on the expected neighbor id, then waits for
/// the geometric effect — deliberately act-then-verify throughout: paneru's
/// protocol has no compare-and-swap, so a check before the act could not
/// close the race anyway. The viewport wait is the point: focusing alone
/// never proved the scroll completed, and an immediate refocus supersedes
/// the animation — so the neighbor must be observed inside the source rect,
/// stable across two reads, before this returns. Bounded (~8x75ms) with
/// early abort on a static frame. Any failure AX-raises the moved window
/// back (or skips silently when there was never anything to center) and
/// returns: the move itself already succeeded.
func centerSource(emit: (String) -> Void) {
  guard !wasFloating, (centerSide == "east" || centerSide == "west"), centerWindowID > 0 else { return }
  guard let start = neighborCenter(),
        let rect = displayContaining(start) else {
    emit("centering skipped: no source rect for neighbor \(centerWindowID)\n")
    return
  }
  if inside(start, rect) {
    emit("source neighbor \(centerWindowID) already in viewport, skipping centering\n")
    return
  }
  let (code, _, err) = runPaneruCLI(["send-cmd", "window", "focus", centerSide])
  guard code == 0 else {
    emit("source focus \(centerSide) failed: \(err)\n")
    return
  }
  guard let fid = queryFocusedWindowID() else {
    emit("centering verify unreadable; raising moved window \(windowID) back\n")
    AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    return
  }
  guard fid == centerWindowID else {
    emit("centering verify failed: focused=\(fid), expected neighbor \(centerWindowID); raising moved window \(windowID) back\n")
    AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    return
  }
  var prevInside = false
  var last: CGPoint? = nil
  var still = 0
  var lastSeen: CGPoint? = nil
  for i in 0..<8 {
    if i > 0 { Thread.sleep(forTimeInterval: 0.075) }
    guard let c = neighborCenter() else { break }
    lastSeen = c
    if inside(c, rect) {
      if prevInside {
        emit("centered source \(centerSide) neighbor \(centerWindowID) at \(describe(c))\n")
        return
      }
      prevInside = true
    } else {
      prevInside = false
      if let l = last, abs(l.x - c.x) < 0.5 && abs(l.y - c.y) < 0.5 { still += 1 }
      else { still = 0; last = c }
      if still >= 3 { break }
    }
  }
  emit("source viewport never centered neighbor \(centerWindowID) (last \(describe(lastSeen)))\n")
}

/// Warp to the window's live center: fullwidth resizes it after the
/// pre-settle warp, so re-resolve geometry instead of reusing the landing
/// point. Same-process re-warp — no extra helper spawn like the Lua side
/// used to pay for this.
func rewarpLive() {
  let size = readSize(window)
  let pos = readPosition(window)
  if size.width > 0 && size.height > 0 {
    warpTo(CGPoint(x: pos.x + size.width / 2, y: pos.y + size.height / 2))
  } else {
    warpTo(pos)
  }
}

if settle() {
  rewarpLive()
  reportElapsed()
  exit(0)
}
// First settle missed — a focus race likely sent fullwidth at the wrong
// window. Raise again to restore macOS focus, wait briefly for paneru to
// track it, and settle once more before giving up.
FileHandle.standardError.write(
  "window \(windowID) not adopted by display \(targetDisplayID) after first settle; retrying\n"
    .data(using: .utf8)!)
AXUIElementPerformAction(window, kAXRaiseAction as CFString)
Thread.sleep(forTimeInterval: 0.1)

// First attempt: fullwidth, then overlap the adoption poll (main thread)
// with source centering (background thread). Safe: the poll reads
// display_id (focus-independent) while centering changes focus (doesn't
// affect display_id) — no shared state, so total time is max(poll, bg),
// never more than sequential. The AX element is touched only before launch
// (teleport/raise above) and after join (rewarp below), never concurrently.
//
// To disable the overlap: delete the group lines and call
// centerSource { FileHandle.standardError.write($0.data(using: .utf8)!) }
// inline here instead.
final class CenterLog: @unchecked Sendable {
  private var lines: [String] = []
  private let lock = NSLock()
  func append(_ line: String) {
    lock.lock()
    lines.append(line)
    lock.unlock()
  }
  func take() -> [String] {
    lock.lock()
    defer { lock.unlock() }
    return lines
  }
}

var adopted = false
if runFullwidth() {
  let group = DispatchGroup()
  let centerLog = CenterLog()
  group.enter()
  DispatchQueue.global(qos: .userInitiated).async {
    centerSource { centerLog.append($0) }
    group.leave()
  }
  adopted = pollAdoption()
  // Unbounded wait is no worse than status quo: every CLI call in this
  // helper already blocks unboundedly on the same daemon, so a wedged
  // daemon hangs the main thread identically with or without threads.
  group.wait()
  for line in centerLog.take() {
    FileHandle.standardError.write(line.data(using: .utf8)!)
  }
}
if !adopted {
  // Retry stays single-threaded by design: the background work already
  // joined above, so nothing runs concurrently here.
  FileHandle.standardError.write(
    "window \(windowID) not adopted by display \(targetDisplayID) after first settle; retrying\n"
      .data(using: .utf8)!)
  AXUIElementPerformAction(window, kAXRaiseAction as CFString)
  Thread.sleep(forTimeInterval: 0.1)
  adopted = settle()
}
guard adopted else {
  FileHandle.standardError.write(
    "window \(windowID) did not settle on display \(targetDisplayID) after retry\n"
      .data(using: .utf8)!)
  exit(1)
}
rewarpLive()
reportElapsed()
