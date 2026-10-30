use crate::*;
use serde_json::{json, Value};
use std::{
    os::unix::fs::{symlink, PermissionsExt},
    time::{SystemTime, UNIX_EPOCH},
};
const COMPONENTS: [&str; 7] = [
    "hypr",
    "waybar",
    "rofi",
    "mako",
    "foot",
    "wlogout",
    "fastfetch",
];
const CORE: &[(&str, &str)] = &[
    ("hyprland", "Hyprland"),
    ("waybar", "waybar"),
    ("rofi", "rofi"),
    ("mako", "mako"),
    ("foot", "foot"),
    ("wlogout", "wlogout"),
    ("hyprpaper", "hyprpaper"),
    ("hypridle", "hypridle"),
    ("hyprlock", "hyprlock"),
    ("wireplumber", "wpctl"),
    ("brightnessctl", "brightnessctl"),
    ("cliphist", "cliphist"),
    ("wl-clipboard", "wl-copy"),
    ("grim", "grim"),
    ("slurp", "slurp"),
    ("ttf-jetbrains-mono-nerd", ""),
    ("playerctl", "playerctl"),
    ("libnotify", "notify-send"),
    ("pacman-contrib", "checkupdates"),
    (
        "hyprpolkitagent",
        "/usr/lib/hyprpolkitagent/hyprpolkitagent",
    ),
    ("xdg-desktop-portal-hyprland", ""),
    ("xdg-desktop-portal-gtk", ""),
    ("xdg-utils", "xdg-open"),
    ("fastfetch", "fastfetch"),
    ("gtk4", ""),
    ("json-c", ""),
];
const OPTIONAL: &[(&str, &str)] = &[
    ("pamixer", "pamixer"),
    ("satty", "satty"),
    ("tesseract", "tesseract"),
    ("tesseract-data-eng", ""),
    ("network-manager-applet", "nm-applet"),
    ("blueman", "blueman-manager"),
    ("pavucontrol", "pavucontrol"),
    ("thunar", "thunar"),
    ("firefox", "firefox"),
];
fn present(p: &Path) -> bool {
    fs::symlink_metadata(p).is_ok()
}
fn remove(p: &Path) -> Result {
    if let Ok(m) = fs::symlink_metadata(p) {
        if m.is_dir() {
            fs::remove_dir_all(p)?;
        } else {
            fs::remove_file(p)?;
        }
    }
    Ok(())
}
fn copy(src: &Path, dst: &Path) -> Result {
    checked("cp", &["-a", "--", string(src), string(dst)])?;
    Ok(())
}
fn unique(parent: &Path, prefix: &str) -> Result<PathBuf> {
    fs::create_dir_all(parent)?;
    for i in 0..100 {
        let p = parent.join(format!(
            "{prefix}{}-{}-{i}",
            SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos(),
            std::process::id()
        ));
        match fs::create_dir(&p) {
            Ok(()) => return Ok(p),
            Err(e) if e.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(e) => return Err(e.into()),
        }
    }
    Err(error("Cannot create staging directory"))
}
fn manifest(snapshot: &Path) -> Result<Value> {
    let m: Value = serde_json::from_slice(&fs::read(snapshot.join("manifest.json"))?)?;
    if !Path::new(m["config"].as_str().ok_or("Missing config")?).is_absolute()
        || m["components"].as_object().is_none_or(|o| {
            o.len() != COMPONENTS.len()
                || COMPONENTS
                    .iter()
                    .any(|n| !o.get(*n).is_some_and(Value::is_boolean))
        })
    {
        return Err(error("Invalid backup manifest"));
    }
    Ok(m)
}
fn restore(snapshot: &Path, dry: bool) -> Result {
    let m = manifest(snapshot)?;
    let config = Path::new(m["config"].as_str().unwrap());
    if dry {
        println!(
            "Would restore {} to {}",
            snapshot.display(),
            config.display()
        );
        return Ok(());
    }
    let stage = unique(config, ".minimal-restore-")?;
    let result: Result = (|| {
        for n in COMPONENTS {
            if m["components"][n] == true {
                copy(&snapshot.join("original").join(n), &stage.join(n))?;
            }
        }
        for n in COMPONENTS {
            remove(&config.join(n))?;
            if m["components"][n] == true {
                fs::rename(stage.join(n), config.join(n))?;
            }
        }
        Ok(())
    })();
    let _ = fs::remove_dir_all(stage);
    result?;
    println!("Restored {}", snapshot.display());
    Ok(())
}
fn deploy(root: &Path, config: &Path, state: &Path, dry: bool) -> Result {
    for n in COMPONENTS {
        if !root.join(n).is_dir() {
            return Err(error(format!("Missing component {n}")));
        }
    }
    if dry {
        for n in COMPONENTS {
            println!(
                "Would back up {} and link to {}",
                config.join(n).display(),
                root.join(n).display()
            );
        }
        return Ok(());
    }
    let is_link = |p: &Path, target: &Path| {
        p.is_symlink() && p.canonicalize().ok().as_deref() == Some(target)
    };
    if COMPONENTS
        .iter()
        .all(|n| is_link(&config.join(n), &root.join(n)))
    {
        println!("All components already linked; recovery point retained.");
        return Ok(());
    }
    let prior = PathBuf::from(text(&state.join("latest_backup")));
    let previous = manifest(&prior)
        .ok()
        .filter(|m| m["config"].as_str() == config.to_str());
    let snapshot = unique(&state.join("backups"), "backup-")?;
    fs::create_dir(snapshot.join("original"))?;
    let mut m = json!({"version":1,"config":config,"root":root,"components":{}});
    // Exact current state is moved aside during deployment, independently of original recovery data.
    for n in COMPONENTS {
        let dest = config.join(n);
        let owned = is_link(&dest, &root.join(n))
            || previous.as_ref().is_some_and(|m| {
                is_link(&dest, &Path::new(m["root"].as_str().unwrap_or("")).join(n))
            });
        let source = if owned {
            previous
                .as_ref()
                .filter(|m| m["components"][n] == true)
                .map(|_| prior.join("original").join(n))
        } else {
            present(&dest).then_some(dest)
        };
        m["components"][n] = json!(source.is_some());
        if let Some(source) = source {
            copy(&source, &snapshot.join("original").join(n))?;
        }
    }
    atomic(
        &snapshot.join("manifest.json"),
        serde_json::to_vec_pretty(&m)?,
    )?;
    fs::copy(env::current_exe()?, snapshot.join("minimal"))?;
    fs::set_permissions(snapshot.join("minimal"), fs::Permissions::from_mode(0o755))?;
    atomic(&snapshot.join("restore.sh"),"#!/usr/bin/env bash\nset -euo pipefail\nbase=$(dirname \"$(readlink -f \"${BASH_SOURCE[0]}\")\")\nexec \"$base/minimal\" install --restore \"$base\" \"$@\"\n")?;
    fs::set_permissions(
        snapshot.join("restore.sh"),
        fs::Permissions::from_mode(0o755),
    )?;
    let stage = unique(config, ".minimal-stage-")?;
    fs::create_dir(stage.join("old"))?;
    let mut touched = Vec::new();
    let result: Result = (|| {
        for n in COMPONENTS {
            symlink(root.join(n), stage.join(n))?;
        }
        for n in COMPONENTS {
            let existed = present(&config.join(n));
            if existed {
                fs::rename(config.join(n), stage.join("old").join(n))?;
            }
            touched.push((n, existed));
            fs::rename(stage.join(n), config.join(n))?;
        }
        atomic(
            &state.join("latest_backup"),
            format!("{}\n", snapshot.display()),
        )?;
        Ok(())
    })();
    if let Err(e) = result {
        for (n, existed) in touched.into_iter().rev() {
            remove(&config.join(n))?;
            if existed {
                fs::rename(stage.join("old").join(n), config.join(n))?;
            }
        }
        let _ = fs::remove_dir_all(stage);
        let _ = fs::remove_dir_all(snapshot);
        return Err(e);
    }
    fs::remove_dir_all(stage)?;
    println!(
        "Deployed Minimal. Recovery: {}",
        snapshot.join("restore.sh").display()
    );
    Ok(())
}
fn missing(packages: &[(&str, &str)]) -> Vec<String> {
    packages
        .iter()
        .filter(|(p, b)| {
            !(!b.is_empty() && (exists(b) || Path::new(b).is_file()))
                && !run("pacman", &["-Qq", p]).is_ok_and(|o| o.status.success())
        })
        .map(|(p, _)| p.to_string())
        .collect()
}
fn confirm(prompt: &str) -> Result<bool> {
    print!("{prompt} [y/N]: ");
    io::stdout().flush()?;
    let mut s = String::new();
    io::stdin().read_line(&mut s)?;
    Ok(["y", "yes"].contains(&s.trim().to_lowercase().as_str()))
}
fn review(dry: bool, config: &Path) -> Result<bool> {
    use std::io::Read;
    struct Terminal(libc::termios);
    impl Drop for Terminal {
        fn drop(&mut self) {
            unsafe {
                libc::tcsetattr(0, libc::TCSANOW, &self.0);
            }
            print!("\x1b[?25h\x1b[?1049l");
            let _ = io::stdout().flush();
        }
    }
    let mut old = unsafe { std::mem::zeroed::<libc::termios>() };
    if unsafe { libc::tcgetattr(0, &mut old) } != 0 {
        return Err(io::Error::last_os_error().into());
    }
    let _terminal = Terminal(old);
    let mut raw = old;
    raw.c_lflag &= !(libc::ICANON | libc::ECHO | libc::ISIG);
    raw.c_cc[libc::VMIN] = 0;
    raw.c_cc[libc::VTIME] = 1;
    if unsafe { libc::tcsetattr(0, libc::TCSANOW, &raw) } != 0 {
        return Err(io::Error::last_os_error().into());
    }
    print!("\x1b[?1049h\x1b[?25l");
    let lines = vec![
        "MINIMAL / Desktop setup".to_owned(),
        String::new(),
        if dry {
            "Preview only"
        } else {
            "Install with a recoverable configuration backup"
        }
        .into(),
        format!("Destination: {}", config.display()),
        String::new(),
        "Hyprland  /  Waybar  /  Rofi  /  Mako".into(),
        "Foot  /  Wlogout  /  Fastfetch".into(),
        String::new(),
        "Your existing configurations are backed up before replacement.".into(),
        "Package installation is handled after this screen.".into(),
        String::new(),
        "Enter: continue    Esc or q: cancel".into(),
    ];
    let mut previous = (0, 0);
    loop {
        let mut size = unsafe { std::mem::zeroed::<libc::winsize>() };
        unsafe {
            libc::ioctl(1, libc::TIOCGWINSZ, &mut size);
        }
        let dimensions = (size.ws_row.max(3), size.ws_col.max(2));
        if dimensions != previous {
            print!("\x1b[2J\x1b[H");
            for line in lines.iter().take(dimensions.0.saturating_sub(2) as usize) {
                println!(
                    "{}\r",
                    line.chars()
                        .take(dimensions.1.saturating_sub(1) as usize)
                        .collect::<String>()
                );
            }
            io::stdout().flush()?;
            previous = dimensions;
        }
        let mut key = [0];
        if io::stdin().read(&mut key)? > 0 {
            match key[0] {
                10 | 13 => return Ok(true),
                3 | 27 | b'q' => return Ok(false),
                _ => (),
            }
        }
    }
}
fn doctor() -> Result {
    config::check()?;
    let o = checked(
        "Hyprland",
        &[
            "--config",
            string(&root().join("hypr/hyprland.lua")),
            "--verify-config",
        ],
    )?;
    if !format!(
        "{}{}",
        String::from_utf8_lossy(&o.stdout),
        String::from_utf8_lossy(&o.stderr)
    )
    .to_lowercase()
    .contains("config ok")
    {
        return Err(error("Hyprland did not report config ok"));
    }
    if let Ok(over) = env::var("HYPRLAND_CONFIG") {
        if !over.is_empty()
            && Path::new(&over).canonicalize().ok()
                != xdg("XDG_CONFIG_HOME", ".config")
                    .join("hypr/hyprland.lua")
                    .canonicalize()
                    .ok()
        {
            return Err(error("HYPRLAND_CONFIG overrides Minimal"));
        }
    }
    let missing = missing(CORE);
    if !missing.is_empty() {
        return Err(error(format!(
            "Missing core packages: {}",
            missing.join(", ")
        )));
    }
    if !root().join("build/minimal-carousel").is_file() {
        return Err(error("Native carousel not built; run scripts/build.sh"));
    }
    println!("PASS: dependencies and Hyprland configuration. Live rendering and suspend/resume need a session test.");
    Ok(())
}
pub fn main(args: &[String]) -> Result {
    let has = |s: &str| args.iter().any(|a| a == s);
    if has("--help") || has("-h") {
        println!("Minimal installer: --doctor | --dry-run | --restore [SNAPSHOT] | --uninstall\nOptions: --skip-packages --all-packages --yes --no-tui");
        return Ok(());
    }
    for (i, a) in args.iter().enumerate() {
        if ![
            "--doctor",
            "--dry-run",
            "--restore",
            "--uninstall",
            "--skip-packages",
            "--all-packages",
            "--yes",
            "-y",
            "--no-tui",
        ]
        .contains(&a.as_str())
            && !(i > 0 && args[i - 1] == "--restore" && !a.starts_with('-'))
        {
            return Err(error(format!("Unknown option: {a}")));
        }
    }
    let dry = has("--dry-run");
    let yes = has("--yes") || has("-y");
    let config = xdg("XDG_CONFIG_HOME", ".config");
    let state = state();
    if !config.is_absolute() || !state.is_absolute() {
        return Err(error("XDG directories must be absolute"));
    }
    if has("--doctor") {
        return doctor();
    }
    if has("--restore") || has("--uninstall") {
        let selected = args
            .iter()
            .position(|s| s == "--restore")
            .and_then(|i| args.get(i + 1))
            .filter(|s| !s.starts_with('-'))
            .cloned()
            .unwrap_or_else(|| text(&state.join("latest_backup")));
        let snapshot = Path::new(&selected).canonicalize()?;
        if dry {
            return restore(&snapshot, true);
        }
        let _guard = lock(&state.join("install.lock"), false)?;
        return restore(&snapshot, false);
    }
    let root = root().canonicalize()?;
    config::validate(&root.join("waybar/config.jsonc"))?;
    for p in config::walk(&root.join("waybar/layouts")) {
        if p.extension().is_some_and(|e| e == "jsonc") {
            config::validate(&p)?;
        }
    }
    for n in COMPONENTS {
        if !root.join(n).is_dir() {
            return Err(error(format!("Missing component {n}")));
        }
    }
    use std::io::IsTerminal;
    if !yes && !has("--no-tui") && io::stdin().is_terminal() && !review(dry, &config)? {
        return Ok(());
    }
    if !has("--skip-packages") {
        let mut packages = CORE.to_vec();
        if has("--all-packages") {
            packages.extend_from_slice(OPTIONAL);
        }
        let missing = missing(&packages);
        if !missing.is_empty() {
            println!("Missing packages: {}", missing.join(" "));
            if !dry {
                for p in &missing {
                    if !run("pacman", &["-Si", p]).is_ok_and(|o| o.status.success()) {
                        return Err(error(format!("{p} unavailable in pacman repositories; supply it separately or use --skip-packages")));
                    }
                }
                if !yes && !confirm("Install missing packages with pacman?")? {
                    return Ok(());
                }
                let mut cmd = Command::new("sudo");
                cmd.args(["pacman", "-S", "--needed"]);
                if yes {
                    cmd.arg("--noconfirm");
                }
                if !cmd.args(missing).status()?.success() {
                    return Err(error("Package installation failed"));
                }
            }
        }
    }
    if dry {
        deploy(&root, &config, &state, true)?;
        println!("Dry run complete; no files changed.");
        return Ok(());
    }
    let _guard = lock(&state.join("install.lock"), false)?;
    deploy(&root, &config, &state, false)?;
    let dest = xdg("XDG_DATA_HOME", ".local/share").join("minimal/wallpapers");
    if !present(&dest)
        && !yes
        && io::stdin().is_terminal()
        && confirm("Download/link the optional wallpaper collection?")?
    {
        let local = home().join("Documents/Wallpapers");
        if local.is_dir() {
            fs::create_dir_all(dest.parent().unwrap())?;
            symlink(local, dest)?;
        } else {
            Command::new(root.join("scripts/wallpaper-pack.sh")).status()?;
        }
    }
    println!("Start a fresh Hyprland session to activate Minimal.");
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn deployment_roundtrip_preserves_originals() {
        let base = unique(&env::temp_dir(), "minimal-native-test-").unwrap();
        let root = base.join("checkout with spaces");
        let config = base.join("config");
        let state = base.join("state");
        for n in COMPONENTS {
            fs::create_dir_all(root.join(n)).unwrap();
        }
        fs::create_dir_all(config.join("hypr")).unwrap();
        fs::write(config.join("hypr/original"), "keep").unwrap();
        symlink("missing", config.join("rofi")).unwrap();
        deploy(&root, &config, &state, true).unwrap();
        assert!(!state.exists());
        deploy(&root, &config, &state, false).unwrap();
        let first = text(&state.join("latest_backup"));
        deploy(&root, &config, &state, false).unwrap();
        assert_eq!(first, text(&state.join("latest_backup")));
        fs::remove_file(config.join("foot")).unwrap();
        fs::write(config.join("foot"), "changed").unwrap();
        deploy(&root, &config, &state, false).unwrap();
        restore(Path::new(&text(&state.join("latest_backup"))), false).unwrap();
        assert_eq!(text(&config.join("hypr/original")), "keep");
        assert_eq!(text(&config.join("foot")), "changed");
        assert_eq!(
            fs::read_link(config.join("rofi")).unwrap(),
            PathBuf::from("missing")
        );
        assert!(!present(&config.join("waybar")));
        fs::remove_dir_all(base).unwrap();
    }
}
