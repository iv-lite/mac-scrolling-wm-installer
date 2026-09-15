use serde::{Deserialize, Serialize};
use std::fmt;
use std::path::Path;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Cheatsheet {
    pub app: String,
    pub config_path: String,
    pub groups: Vec<Group>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Group {
    pub name: String,
    pub items: Vec<Item>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Item {
    pub action: String,
    pub keys: Vec<String>,
}

#[derive(Debug)]
pub enum Error {
    Io(std::io::Error),
    Json(serde_json::Error),
    Invalid(String),
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Error::Io(e) => write!(f, "cannot read cheatsheet: {e}"),
            Error::Json(e) => write!(f, "cannot parse cheatsheet: {e}"),
            Error::Invalid(msg) => write!(f, "invalid cheatsheet: {msg}"),
        }
    }
}

impl std::error::Error for Error {}

pub fn load(path: &Path) -> Result<Cheatsheet, Error> {
    let raw = std::fs::read_to_string(path).map_err(Error::Io)?;
    parse(&raw)
}

pub fn parse(raw: &str) -> Result<Cheatsheet, Error> {
    let sheet: Cheatsheet = serde_json::from_str(raw).map_err(Error::Json)?;
    validate(&sheet)?;
    Ok(sheet)
}

fn validate(sheet: &Cheatsheet) -> Result<(), Error> {
    if sheet.groups.is_empty() {
        return Err(Error::Invalid("no groups".to_string()));
    }
    for group in &sheet.groups {
        let name = group.name.trim();
        if name.is_empty() {
            return Err(Error::Invalid("group with empty name".to_string()));
        }
        for item in &group.items {
            let action = item.action.trim();
            if action.is_empty() {
                return Err(Error::Invalid(format!(
                    "item in group '{name}' has an empty action"
                )));
            }
            if item.keys.is_empty() {
                return Err(Error::Invalid(format!("item '{action}' has no keys")));
            }
            for key in &item.keys {
                if key.trim().is_empty() {
                    return Err(Error::Invalid(format!("item '{action}' has an empty key")));
                }
            }
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE: &str = r#"{
        "app": "Paneru",
        "config_path": "/Users/x/.config/paneru/init.lua",
        "groups": [
            {
                "name": "Focus",
                "items": [
                    { "action": "Focus window west", "keys": ["Cmd+Option+Left"] }
                ]
            }
        ]
    }"#;

    #[test]
    fn parses_valid_cheatsheet() {
        let sheet = parse(SAMPLE).unwrap();
        assert_eq!(sheet.app, "Paneru");
        assert_eq!(sheet.groups.len(), 1);
        assert_eq!(sheet.groups[0].items[0].keys, vec!["Cmd+Option+Left"]);
    }

    #[test]
    fn rejects_missing_keys() {
        let raw = r#"{ "app": "Paneru", "config_path": "/x", "groups": [
            { "name": "Focus", "items": [ { "action": "Focus west", "keys": [] } ] }
        ] }"#;
        let err = parse(raw).unwrap_err();
        assert!(matches!(err, Error::Invalid(_)));
    }

    #[test]
    fn rejects_empty_action() {
        let raw = r#"{ "app": "Paneru", "config_path": "/x", "groups": [
            { "name": "Focus", "items": [ { "action": " ", "keys": ["Cmd+Option+Left"] } ] }
        ] }"#;
        assert!(matches!(parse(raw), Err(Error::Invalid(_))));
    }

    #[test]
    fn rejects_missing_app_field() {
        let raw = r#"{ "config_path": "/x", "groups": [] }"#;
        assert!(matches!(parse(raw), Err(Error::Json(_))));
    }

    #[test]
    fn rejects_unknown_field() {
        let raw = r#"{ "app": "Paneru", "config_path": "/x", "bogus": 1, "groups": [
            { "name": "Focus", "items": [ { "action": "a", "keys": ["b"] } ] }
        ] }"#;
        assert!(matches!(parse(raw), Err(Error::Json(_))));
    }

    #[test]
    fn rejects_non_object() {
        assert!(matches!(parse("[]"), Err(Error::Json(_))));
    }
}
