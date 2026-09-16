// focus-display — warp the pointer to a given point (v2, warp-only).
//
// Usage: focus-display <x> <y>
//
// Previous versions enumerated displays, located the mouse's display, and
// asked paneru (`query on-screen` + JSON parse) which window to warp to.
// That lookup now lives in config/paneru/lib/displays.lua, resolved
// in-process via paneru.query_json("state") with zero subprocesses; this
// binary does only what needs a compiled identity: warp the pointer and
// post the synthetic .mouseMoved event. CGWarpMouseCursorPosition alone
// posts no event to any CGEventTap, including paneru's focus_follows_mouse
// tap, so the event is what makes the warp take effect as focus (not a
// click — nothing on screen should be clicked just to focus it).
//
// The source path and installed binary name are unchanged on purpose: the
// one-time Accessibility grant macOS ties to this binary keeps applying,
// and no Lua call site or install path has to change.
//
// Needs Accessibility access granted to this specific compiled binary (a
// one-time macOS prompt) — posting a synthetic CGEvent is TCC-gated, which
// is why this is compiled once (see scripts/install-helpers) instead of run
// as an ephemeral `swift -e` script: an ephemeral process gets a fresh,
// effectively anonymous identity every run and could never hold the grant.
import CoreGraphics
import Foundation

let args = CommandLine.arguments
guard args.count == 3, let x = Double(args[1]), let y = Double(args[2]) else {
  FileHandle.standardError.write("usage: focus-display <x> <y>\n".data(using: .utf8)!)
  exit(1)
}
let point = CGPoint(x: x, y: y)
CGWarpMouseCursorPosition(point)
CGAssociateMouseAndMouseCursorPosition(1)
CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
        mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
