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
- `src-tauri` — the app: `src/lib.rs` reads argv[1], parses with
  `cheatsheet-core`, and serves the data to the frontend through the
  `get_cheatsheet` command (`withGlobalTauri` is on, so nothing needs bundling
  beyond the static assets). There is **no `devUrl` and no dev server**: Tauri
  embeds `frontend/dist` (dev uses its built-in static serving, release embeds
  it), so the app can never launch against an unreachable server.
- `frontend/` — web asset sources (`index.html`, `style.css`, `app.js`);
  `frontend/build.sh` stages them into `frontend/dist/` (Tauri's
  `frontendDist`). `tauri dev`/`tauri build` run it automatically via
  `beforeDevCommand`/`beforeBuildCommand`; `install-helpers` also runs it
  explicitly before building.
- `src-tauri/icons/app-icon.png` — icon source (512×512). Bundling icons are
  generated from it with `tauri icon` (done automatically by `install-helpers`).

## Building

```sh
cargo install tauri-cli --locked        # once
cd src-tauri
tauri icon icons/app-icon.png           # if src-tauri/icons is empty
tauri build                             # runs frontend/build.sh, embeds assets,
                                        # produces mac-cheatsheet-viewer.app
```

`cargo tauri dev` works the same way (static serving from `frontend/dist`,
no external server).

The installer copies the resulting `.app` into
`~/.config/mac-scrolling-wm/helpers/`.