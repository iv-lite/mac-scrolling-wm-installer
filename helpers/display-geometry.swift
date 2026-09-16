// display-geometry — enumerate every online display (empty ones included).
//
// Paneru's Lua `display_of` resolves a window's display by *membership* in a
// strip, so a monitor with no windows is invisible to Lua. Navigation to blank
// monitors therefore needs real display geometry, sourced here via
// CGGetOnlineDisplayList + CGDisplayBounds.
//
// Output: one line per display, `id x y w h`, sorted y-ascending so the first
// line is the leftmost display (same geometric convention the Lua
// ordered_displays() used, and the same order paneru's horizontal_mouse_warp
// maps to left-to-right).
//
// Called via `paneru.exec`, which hands the stdout back as a string.
// Installed (compiled) at $HOME/.config/mac-scrolling-wm/helpers/display-geometry.
//
// Compiled once by scripts/install-helpers: the previous `swift -e` wrapper
// paid a 150-400ms JIT-compile tax on every use, and Lua calls this on every
// move/focus dispatch with a stale geometry cache.
import CoreGraphics
import Foundation

var count: UInt32 = 0
CGGetOnlineDisplayList(0, nil, &count)
var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
CGGetOnlineDisplayList(count, &ids, &count)

var rows: [(Int, Int, Int, Int, Int)] = []
for i in 0..<Int(count) {
  let b = CGDisplayBounds(ids[i])
  rows.append((Int(ids[i]), Int(b.origin.x), Int(b.origin.y), Int(b.size.width), Int(b.size.height)))
}
rows.sort { $0.2 == $1.2 ? $0.1 < $1.1 : $0.2 < $1.2 }
for row in rows {
  print("\(row.0) \(row.1) \(row.2) \(row.3) \(row.4)")
}
