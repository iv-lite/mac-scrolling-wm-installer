use cheatsheet_core::load as load_cheatsheet;
use serde::Serialize;
use std::path::PathBuf;
use std::sync::Mutex;
use tauri::{Manager, State};

#[derive(Serialize, Clone)]
struct ViewerData {
    app: String,
    config_path: String,
    groups: Vec<cheatsheet_core::Group>,
    error: Option<String>,
}

struct ViewerState(Mutex<ViewerData>);

fn default_path() -> Option<PathBuf> {
    if let Ok(home) = std::env::var("HOME") {
        return Some(PathBuf::from(home).join(".config/paneru/cheatsheet.json"));
    }
    None
}

#[tauri::command]
fn get_cheatsheet(state: State<'_, ViewerState>) -> ViewerData {
    state.0.lock().unwrap().clone()
}

#[tauri::command]
async fn close_window(window: tauri::Window) {
    let _ = window.close();
}

fn build_viewer_data(json_path: Option<PathBuf>) -> ViewerData {
    let fallback = default_path();
    let path = json_path
        .filter(|p| p.exists())
        .or_else(|| fallback.filter(|p| p.exists()));

    let (path_display, groups, app, error) = match path {
        Some(p) => match load_cheatsheet(&p) {
            Ok(sheet) => (
                p.to_string_lossy().to_string(),
                sheet.groups,
                sheet.app,
                None,
            ),
            Err(err) => (
                p.to_string_lossy().to_string(),
                vec![],
                "Paneru".to_string(),
                Some(err.to_string()),
            ),
        },
        None => (
            "no cheatsheet file found".to_string(),
            vec![],
            "Paneru".to_string(),
            Some(
                "No shortcut JSON was given and no ~/.config/paneru/cheatsheet.json \
                 exists. Run display-shortcuts to generate one."
                    .to_string(),
            ),
        ),
    };

    ViewerData {
        app,
        config_path: path_display,
        groups,
        error,
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let json_path = std::env::args()
        .nth(1)
        .filter(|a| !a.starts_with('-'))
        .map(PathBuf::from);

    tauri::Builder::default()
        .setup(|app| {
            let data = build_viewer_data(json_path);
            app.manage(ViewerState(Mutex::new(data)));
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![get_cheatsheet, close_window])
        .run(tauri::generate_context!())
        .expect("error while running mac-cheatsheet-viewer");
}