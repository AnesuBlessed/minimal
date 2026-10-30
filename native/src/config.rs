use crate::*;
use serde_json::Value;
use std::collections::HashSet;

pub fn parse(text: &str) -> Result<Value> {
    let mut out = Vec::new();
    let bytes = text.as_bytes();
    let (mut i, mut quoted, mut escape) = (0, false, false);
    while i < bytes.len() {
        let b = bytes[i];
        if quoted {
            out.push(b);
            if escape {
                escape = false;
            } else if b == b'\\' {
                escape = true;
            } else if b == b'"' {
                quoted = false;
            }
        } else if b == b'"' {
            quoted = true;
            out.push(b);
        } else if b == b'/' && bytes.get(i + 1) == Some(&b'/') {
            while i < bytes.len() && bytes[i] != b'\n' {
                i += 1;
            }
            out.push(b'\n');
            continue;
        } else if b == b'/' && bytes.get(i + 1) == Some(&b'*') {
            i += 2;
            while i + 1 < bytes.len() && &bytes[i..i + 2] != b"*/" {
                i += 1;
            }
            if i + 1 >= bytes.len() {
                return Err(error("Unterminated comment"));
            }
            i += 2;
            out.push(b' ');
            continue;
        } else {
            out.push(b);
        }
        i += 1;
    }
    let mut clean = Vec::new();
    quoted = false;
    escape = false;
    for (i, &b) in out.iter().enumerate() {
        if !quoted
            && b == b','
            && out[i + 1..]
                .iter()
                .find(|c| !c.is_ascii_whitespace())
                .is_some_and(|c| *c == b'}' || *c == b']')
        {
            continue;
        }
        clean.push(b);
        if quoted && escape {
            escape = false;
        } else if quoted && b == b'\\' {
            escape = true;
        } else if b == b'"' {
            quoted = !quoted;
        }
    }
    Ok(serde_json::from_slice(&clean)?)
}
fn resolve(path: &Path, seen: &mut HashSet<PathBuf>) -> Result<Value> {
    let path = path.canonicalize()?;
    if !seen.insert(path.clone()) {
        return Err(error("Circular config include"));
    }
    let mut data = parse(&fs::read_to_string(&path)?)?
        .as_object()
        .ok_or("Expected object")?
        .clone();
    if let Some(includes) = data.remove("include") {
        for item in includes.as_array().ok_or("Expected include array")? {
            let child = resolve(
                &path
                    .parent()
                    .unwrap()
                    .join(item.as_str().ok_or("Invalid include")?),
                seen,
            )?;
            for (k, v) in child.as_object().unwrap() {
                data.entry(k).or_insert(v.clone());
            }
        }
    }
    seen.remove(&path);
    Ok(Value::Object(data))
}
pub fn validate(path: &Path) -> Result<Value> {
    let data = resolve(path, &mut HashSet::new())?;
    fn modules(data: &Value, names: &Value, stack: &mut HashSet<String>) -> Result {
        for name in names.as_array().ok_or("Expected module list")? {
            let name = name.as_str().ok_or("Invalid module name")?;
            let value = data
                .get(name)
                .ok_or_else(|| error(format!("Undefined module {name}")))?;
            if name.starts_with("group/") {
                if !stack.insert(name.to_string()) {
                    return Err(error("Circular group"));
                }
                modules(data, &value["modules"], stack)?;
                stack.remove(name);
            }
        }
        Ok(())
    }
    for side in ["left", "center", "right"] {
        if let Some(names) = data.get(format!("modules-{side}")) {
            modules(&data, names, &mut HashSet::new())?;
        }
    }
    Ok(data)
}
pub fn walk(path: &Path) -> Vec<PathBuf> {
    let mut all = Vec::new();
    if let Ok(entries) = fs::read_dir(path) {
        for entry in entries.flatten() {
            let p = entry.path();
            if entry.file_type().is_ok_and(|f| f.is_dir()) {
                all.extend(walk(&p));
            } else if p.is_file() {
                all.push(p);
            }
        }
    }
    all.sort();
    all
}
pub fn check() -> Result {
    for path in walk(&root().join("scripts")) {
        if path.extension().is_some_and(|e| e == "sh") {
            checked("bash", &["-n", string(&path)])?;
        }
    }
    checked("bash", &["-n", string(&root().join("install.sh"))])?;
    for path in walk(&root().join("hypr")) {
        if path.extension().is_some_and(|e| e == "lua") && exists("luac") {
            checked("luac", &["-p", string(&path)])?;
        }
    }
    validate(&root().join("waybar/config.jsonc"))?;
    for path in walk(&root().join("waybar/layouts")) {
        if path.extension().is_some_and(|e| e == "jsonc") {
            validate(&path)?;
        }
    }
    if exists("rofi") {
        for path in walk(&root().join("rofi")) {
            if path.extension().is_some_and(|e| e == "rasi") {
                checked(
                    "rofi",
                    &["-no-config", "-theme", string(&path), "-dump-theme"],
                )?;
            }
        }
    }
    if exists("foot") {
        checked(
            "foot",
            &[
                "--check-config",
                &format!("--config={}", root().join("foot/foot.ini").display()),
            ],
        )?;
    }
    println!("PASS: shell syntax, available Lua/Rofi/Foot parsers, bar includes and modules");
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn comments_preserve_strings() {
        let v = parse("{/*x*/\"url\":\"https://x/a,}\",//x\n\"a\":[1,2,],}").unwrap();
        assert_eq!(v["url"], "https://x/a,}");
        assert_eq!(v["a"], serde_json::json!([1, 2]));
    }
    #[test]
    fn bad_comment_rejected() {
        assert!(parse("{/*oops").is_err());
    }
    #[test]
    fn shipped_layouts_validate() {
        validate(&root().join("waybar/config.jsonc")).unwrap();
        validate(&root().join("waybar/layouts/01.jsonc")).unwrap();
    }
}
