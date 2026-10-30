use crate::*;
use base64::{engine::general_purpose::STANDARD, Engine};
use serde_json::{json, Value};
use std::os::unix::process::CommandExt;

pub fn rofi_images(mode: &str) -> String {
    let mut s = fs::read_to_string(state().join("theme/rofi.rasi")).unwrap_or_default();
    let widgets = if ["clipboard", "selector"].contains(&mode) {
        [("wallbox", "blur", "width"), ("wallframe", "quad", "width")]
    } else {
        [
            ("dummywall", "thmb", "height"),
            ("mode-switcher", "blur", "height"),
        ]
    };
    for (widget, suffix, scale) in widgets {
        s += &format!(
            "\n{widget} {{ background-image: url({}, {scale}); }}\n",
            json!(cache().join(format!("wall.{suffix}")))
        );
    }
    s
}
fn placement_rule(data: Option<Value>) -> String {
    let data = data.unwrap_or(Value::Null);
    let offset = data["height"].as_i64().unwrap_or(34).max(34) + 14;
    let rules =
        match data["position"]
            .as_str()
            .unwrap_or(if data.is_object() { "top" } else { "unknown" })
        {
            "top" => format!(
                "location: north east; anchor: north east; x-offset: -12px; y-offset: {offset}px;"
            ),
            "bottom" => format!(
                "location: south east; anchor: south east; x-offset: -12px; y-offset: -{offset}px;"
            ),
            "left" => "location: west; anchor: west; x-offset: 60px; y-offset: 0px;".into(),
            "right" => "location: east; anchor: east; x-offset: -60px; y-offset: 0px;".into(),
            _ => "location: center; anchor: center; x-offset: 0px; y-offset: 0px;".into(),
        };
    format!("window {{ {rules} }}")
}
pub fn placement() -> Result {
    println!(
        "{}",
        placement_rule(serde_json::from_str(&text(&state().join("waybar.json"))).ok())
    );
    Ok(())
}
fn header(key: &str, value: &str) {
    println!("\0{key}\x1f{value}");
}
fn entry(value: &str, info: &str, disabled: bool) {
    let safe: String = value
        .chars()
        .map(|c| if c.is_control() { ' ' } else { c })
        .collect();
    println!(
        "{safe}\0info\x1f{info}{}",
        if disabled {
            "\x1fnonselectable\x1ftrue\x1fpermanent\x1ftrue"
        } else {
            ""
        }
    );
}
fn history() -> Result {
    let o = checked("cliphist", &["list"])?;
    if o.stdout.is_empty() {
        entry("Clipboard is empty", "", true);
    }
    for row in o.stdout.split(|c| *c == b'\n').filter(|r| !r.is_empty()) {
        if let Some(tab) = row.iter().position(|c| *c == b'\t') {
            entry(
                &String::from_utf8_lossy(&row[tab + 1..]),
                &STANDARD.encode(row),
                false,
            );
        }
    }
    Ok(())
}
pub fn clipboard() -> Result {
    let result = clipboard_action();
    if let Err(e) = result {
        eprintln!("Clipboard: {e}");
        header("data", "history");
        entry("Clipboard action failed — try again", "", true);
    }
    Ok(())
}
fn clipboard_action() -> Result {
    let get = |name| env::var(name).unwrap_or_default();
    let action = get("ROFI_RETV");
    let state = get("ROFI_DATA");
    let info = get("ROFI_INFO");
    let start = get("MINIMAL_CLIPBOARD_START");
    let initial = action.is_empty() || action == "0";
    let confirm = action == "11" || (initial && start == "--wipe");
    let delete = state == "delete" || (initial && ["--delete", "-d"].contains(&start.as_str()));
    for (k, v) in [
        ("no-custom", "true"),
        ("use-hot-keys", "true"),
        ("keep-selection", "true"),
        (
            "keep-filter",
            if confirm || state == "confirm" {
                "false"
            } else {
                "true"
            },
        ),
    ] {
        header(k, v);
    }
    if state == "confirm" && action == "1" {
        if info == "wipe" {
            checked("cliphist", &["wipe"])?;
        }
    } else if state != "confirm" && ["1", "10"].contains(&action.as_str()) && !info.is_empty() {
        let mut row = STANDARD.decode(info)?;
        let id = row.split(|c| *c == b'\t').next().unwrap_or_default();
        if id.is_empty() || !id.iter().all(u8::is_ascii_digit) {
            return Err(error("Invalid clipboard entry"));
        }
        row.push(b'\n');
        if action == "10" || delete {
            input("cliphist", &["delete"], &row)?;
        } else {
            let decoded = input("cliphist", &["decode"], &row)?;
            input("wl-copy", &[], &decoded.stdout)?;
            return Ok(());
        }
    }
    if confirm {
        header("data", "confirm");
        header("new-selection", "0");
        entry("Cancel", "cancel", false);
        entry("Clear all clipboard history", "wipe", false);
    } else {
        header("data", if delete { "delete" } else { "history" });
        if delete {
            header("prompt", "󰆴 Delete clip");
        }
        history()?;
    }
    Ok(())
}
pub fn terminal(args: &[String]) -> Result {
    let theme = state().join("theme");
    let config = if theme.join("foot.ini").is_file() {
        theme.join("foot.ini")
    } else {
        root().join("foot/foot.ini")
    };
    let rt = xdg("XDG_RUNTIME_DIR", ".cache/minimal/runtime");
    let mut sockets = vec![rt.join("foot.sock")];
    if let Ok(d) = env::var("WAYLAND_DISPLAY") {
        sockets.push(rt.join(format!("foot-{d}.sock")));
    }
    if let Ok(p) = env::var("FOOT_SERVER_PATH") {
        sockets.push(p.into());
    }
    if sockets
        .iter()
        .any(|p| std::os::unix::net::UnixStream::connect(p).is_ok())
    {
        let mut cmd = Command::new("footclient");
        if let Ok(p) = serde_json::from_str::<Value>(&text(&theme.join("palette.json"))) {
            for (key, value) in [
                (
                    "background",
                    p["background"].as_str().unwrap_or("0f1a2a").to_owned(),
                ),
                (
                    "foreground",
                    p["foreground"].as_str().unwrap_or("cce1ff").to_owned(),
                ),
                (
                    "selection-background",
                    p["selection"].as_str().unwrap_or("3a4e6b").to_owned(),
                ),
                (
                    "selection-foreground",
                    p["foreground"].as_str().unwrap_or("cce1ff").to_owned(),
                ),
                (
                    "cursor",
                    format!(
                        "{} {}",
                        p["background"].as_str().unwrap_or("0f1a2a"),
                        p["accent"].as_str().unwrap_or("ca9ee6")
                    ),
                ),
            ] {
                cmd.args(["-o", &format!("colors-dark.{key}={value}")]);
            }
        }
        let _ = cmd.args(args).exec();
    }
    Err(Command::new("foot")
        .arg("--config")
        .arg(config)
        .args(args)
        .exec()
        .into())
}
fn owned_pid(config: &Path) -> Option<i32> {
    let pid = text(&state().join("waybar.pid")).parse::<i32>().ok()?;
    if pid <= 1 {
        return None;
    }
    let bytes = fs::read(format!("/proc/{pid}/cmdline")).ok()?;
    let argv: Vec<_> = bytes.split(|b| *b == 0).collect();
    if Path::new(std::str::from_utf8(argv.first()?).ok()?).file_name()? == "waybar"
        && argv.contains(&string(config).as_bytes())
    {
        Some(pid)
    } else {
        None
    }
}
pub fn bar(args: &[String]) -> Result {
    let layouts: Vec<String> = config::walk(&root().join("waybar/layouts"))
        .into_iter()
        .filter_map(|p| {
            let stem = p.file_stem()?.to_str()?;
            (p.extension()? == "jsonc"
                && stem.len() == 2
                && stem.bytes().all(|c| c.is_ascii_digit()))
            .then(|| stem.to_owned())
        })
        .collect();
    let mut pool = layouts;
    pool.push("custom".into());
    let mut command = args
        .first()
        .map(String::as_str)
        .unwrap_or("next")
        .to_owned();
    if command == "select" {
        let o = input(
            "rofi",
            &[
                "-dmenu",
                "-no-custom",
                "-theme",
                string(&root().join("rofi/selector.rasi")),
                "-theme-str",
                &rofi_images("selector"),
                "-p",
                "Bar layout",
            ],
            pool.join("\n").as_bytes(),
        );
        match o {
            Ok(o) => command = String::from_utf8(o.stdout)?.trim().into(),
            Err(_) => return Ok(()),
        }
    }
    let _lock = lock(&state().join("bar.lock"), false)?;
    let mut current = text(&state().join("current_waybar_layout"));
    if !pool.contains(&current) {
        current = "custom".into();
    }
    let mut target = current.clone();
    if command == "next" || command == "prev" {
        let index = pool.iter().position(|s| s == &current).unwrap();
        target =
            pool[(index + if command == "next" { 1 } else { pool.len() - 1 }) % pool.len()].clone();
    } else if pool.contains(&command) {
        target = command.clone();
    } else if !["start", "reload", "render"].contains(&command.as_str()) {
        return Err(error("Unknown bar command"));
    }
    let source = root().join(if target == "custom" {
        "waybar/config.jsonc".into()
    } else {
        format!("waybar/layouts/{target}.jsonc")
    });
    let mut data = config::validate(&source)?;
    let mut unavailable = Vec::new();
    let mut sensor = None;
    if let Ok(devices) = fs::read_dir("/sys/class/hwmon") {
        for d in devices.flatten() {
            if ["coretemp", "k10temp", "cpu_thermal", "zenpower"]
                .contains(&text(&d.path().join("name")).as_str())
            {
                sensor = config::walk(&d.path()).into_iter().find(|p| {
                    p.file_name().is_some_and(|n| {
                        n.to_string_lossy().starts_with("temp")
                            && n.to_string_lossy().ends_with("_input")
                    })
                });
                if sensor.is_some() {
                    break;
                }
            }
        }
    }
    if let Some(p) = sensor {
        if data["temperature"].is_object() {
            data["temperature"]["hwmon-path"] = json!(p);
        }
    } else {
        unavailable.push("temperature");
    }
    if fs::read_dir("/sys/class/backlight").map_or(true, |mut d| d.next().is_none()) {
        unavailable.extend(["backlight", "group/eyecare"]);
    }
    if !fs::read_dir("/sys/class/power_supply").is_ok_and(|d| {
        d.flatten()
            .any(|p| p.file_name().to_string_lossy().starts_with("BAT"))
    }) {
        unavailable.push("battery");
    }
    fn filter(v: &mut Value, missing: &[&str]) {
        match v {
            Value::Array(a) => {
                a.retain(|v| !v.as_str().is_some_and(|s| missing.contains(&s)));
                for v in a {
                    filter(v, missing);
                }
            }
            Value::Object(o) => {
                for v in o.values_mut() {
                    filter(v, missing);
                }
            }
            _ => (),
        }
    }
    filter(&mut data, &unavailable);
    let config = state().join("waybar.json");
    atomic(&config, serde_json::to_vec_pretty(&data)?)?;
    atomic(
        &state().join("current_waybar_layout"),
        format!("{target}\n"),
    )?;
    if command == "render" {
        println!("{}", config.display());
        return Ok(());
    }
    let style = state().join("waybar.css");
    let mut css = format!("@import {};\n", json!(root().join("waybar/style.css")));
    if state().join("theme/waybar.css").is_file() {
        css += &format!("@import {};\n", json!(state().join("theme/waybar.css")));
    }
    if fs::read_to_string(&style).unwrap_or_default() != css {
        atomic(&style, css)?;
    }
    let mut pid = owned_pid(&config);
    if let Some(p) = pid {
        if !fs::read(format!("/proc/{p}/cmdline"))?
            .split(|b| *b == 0)
            .any(|a| a == string(&style).as_bytes())
        {
            unsafe {
                libc::kill(p, libc::SIGTERM);
            }
            for _ in 0..40 {
                if owned_pid(&config).is_none() {
                    break;
                }
                std::thread::sleep(std::time::Duration::from_millis(50));
            }
            if owned_pid(&config).is_some() {
                return Err(error("Old Waybar did not stop"));
            }
            pid = None;
        }
    }
    if let Some(pid) = pid {
        if command != "start" && unsafe { libc::kill(pid, libc::SIGUSR2) } != 0 {
            return Err(io::Error::last_os_error().into());
        }
    } else {
        let logpath = state().join("waybar.log");
        if fs::metadata(&logpath).is_ok_and(|m| m.len() > 1024 * 1024) {
            let _ = fs::rename(&logpath, state().join("waybar.log.1"));
        }
        let log = fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(logpath)?;
        let mut cmd = Command::new("waybar");
        cmd.args(["-c", string(&config), "-s", string(&style)])
            .env("MINIMAL_ROOT", root())
            .stdout(log.try_clone()?)
            .stderr(log);
        unsafe {
            cmd.pre_exec(|| {
                if libc::setsid() == -1 {
                    return Err(io::Error::last_os_error());
                }
                Ok(())
            });
        }
        let mut child = cmd.spawn()?;
        std::thread::sleep(std::time::Duration::from_millis(200));
        if child.try_wait()?.is_some() {
            return Err(error("Waybar exited; check waybar.log"));
        }
        atomic(&state().join("waybar.pid"), child.id().to_string())?;
    }
    Ok(())
}
fn shell_quote(s: &str) -> String {
    format!("'{}'", s.replace('\'', "'\\''"))
}
pub fn power_files(args: &[String]) -> Result {
    if args.len() != 4 {
        return Err(error(
            "power-files needs input layout/CSS and output layout/CSS",
        ));
    }
    let layout = fs::read_to_string(&args[0])?;
    let mut out = String::new();
    for v in serde_json::Deserializer::from_str(&layout).into_iter::<Value>() {
        let mut v = v?;
        let action = shell_quote(string(&root().join("scripts/lock.sh")));
        match v["label"].as_str().unwrap_or("") {
            "lock" => v["action"] = json!(action),
            "suspend" | "hibernate" => {
                v["action"] = json!(format!(
                    "{action} & sleep 1; systemctl {}",
                    v["label"].as_str().unwrap()
                ))
            }
            _ => (),
        }
        out += &serde_json::to_string(&v)?;
        out.push('\n');
    }
    let mut css = fs::read_to_string(&args[1])?;
    for name in [
        "lock",
        "logout",
        "suspend",
        "hibernate",
        "shutdown",
        "reboot",
    ] {
        css = css.replace(
            &format!("\"icons/{name}_white.png\""),
            &json!(root().join(format!("wlogout/icons/{name}_white.png"))).to_string(),
        );
    }
    fs::write(&args[2], out)?;
    fs::write(&args[3], css)?;
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn bottom_placement() {
        assert!(
            placement_rule(Some(json!({"position":"bottom","height":40})))
                .contains("y-offset: -54px")
        );
    }
    #[test]
    fn missing_placement_centered() {
        assert!(placement_rule(None).contains("location: center"));
    }
}
