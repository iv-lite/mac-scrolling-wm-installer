# mac-cheatsheet-viewer

Borderless always-on-top overlay that renders the Paneru shortcut cheat sheet
from a JSON file passed as its first launch argument (falling back to
`~/.config/paneru/cheatsheet.json`).

Wire-up (all handled by the installer):

- `generate-shortcuts-json` (in `../`) turns `config/paneru/init.lua`'s
  `BINDINGS` table into that JSON.
- `display-shortcuts` (in `../`) regenerates the JSON and opens this app;
  `config/paneru/init.lua` binds it to `Cmd+Shift+?` via `paneru.exec`.

## Layout

- `crates/cheatsheet-core` — pure Rust: schema types + strict JSON
  load/validation. No Tauri; unit-testable anywhere (`cargo test`).
- `src-tauri` — the app: static vanilla frontend (`frontend/`, no npm),
  `src/lib.rs` reads argv[1], parses with `cheatsheet-core`, and serves the
  data to the frontend through the `get_cheatsheet` command. `withGlobalTauri`
  is on, so nothing needs bundling beyond the static assets.
- `src-tauri/icons/app-icon.png` — icon source (512×512). Bundling icons are
  generated from it with `tauri icon` (done automatically by `install-helpers`).

## Building

```sh
cargo install tauri-cli --locked        # once
cd src-tauri
tauri icon icons/app-icon.png           # if src-tauri/icons is empty
tauri build                             # produces mac-cheatsheet-viewer.app
```

The installer copies the resulting `.app` into
`~/.config/mac-scrolling-wm/helpers/`.