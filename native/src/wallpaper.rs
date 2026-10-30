use crate::*;
use serde_json::{json, Value};
use std::{
    collections::HashSet,
    os::unix::fs::{symlink, MetadataExt, PermissionsExt},
    time::Duration,
};
#[derive(Clone)]
pub struct Item {
    pub path: PathBuf,
    pub category: String,
    pub stem: String,
}
pub fn discover() -> Vec<Item> {
    let roots = [
        root().join("wallpapers"),
        xdg("XDG_DATA_HOME", ".local/share").join("minimal/wallpapers"),
        home().join("Documents/Wallpapers"),
        home().join("Pictures/Wallpapers"),
    ];
    let mut seen = HashSet::new();
    let mut items = Vec::new();
    for root in roots {
        for p in config::walk(&root) {
            if !p.extension().is_some_and(|e| {
                ["png", "jpg", "jpeg", "webp"]
                    .contains(&e.to_string_lossy().to_lowercase().as_str())
            }) {
                continue;
            }
            if let Ok(path) = p.canonicalize() {
                if seen.insert(path.clone()) {
                    let rel = p.strip_prefix(&root).unwrap();
                    let category = if rel.components().count() > 1 {
                        rel.components()
                            .next()
                            .unwrap()
                            .as_os_str()
                            .to_string_lossy()
                            .into_owned()
                    } else {
                        root.file_name()
                            .unwrap_or_default()
                            .to_string_lossy()
                            .into_owned()
                    };
                    items.push(Item {
                        path,
                        category,
                        stem: p
                            .file_stem()
                            .unwrap_or_default()
                            .to_string_lossy()
                            .into_owned(),
                    });
                }
            }
        }
    }
    items
}
fn running(name: &str) -> bool {
    run("pgrep", &["-u", &uid(), "-x", name]).is_ok_and(|o| o.status.success())
}
pub fn apply(path: &Path, x: &str, y: &str) -> Result {
    let wall = path.canonicalize()?;
    if !wall.is_file() {
        return Err(error("Wallpaper must be a file"));
    }
    // Validate before asking a daemon to change the desktop.
    let _ = theme::load(&wall)?;
    let _lock = lock(&state().join("wallpaper.lock"), false)?;
    let mut applied = false;
    for daemon in ["awww", "swww"] {
        if exists(daemon)
            && running(&format!("{daemon}-daemon"))
            && run(
                daemon,
                &[
                    "img",
                    string(&wall),
                    "--transition-type",
                    "grow",
                    "--transition-pos",
                    &format!("{x},{y}"),
                    "--transition-duration",
                    "1.2",
                ],
            )
            .is_ok_and(|o| o.status.success())
        {
            applied = true;
            break;
        }
    }
    if !applied {
        if string(&wall).contains(',') {
            return Err(error(
                "Hyprpaper cannot represent commas in wallpaper paths",
            ));
        }
        if !running("hyprpaper") {
            let _ = run("systemctl", &["--user", "start", "hyprpaper.service"]);
            for _ in 0..15 {
                if running("hyprpaper") {
                    break;
                }
                std::thread::sleep(Duration::from_millis(100));
            }
            if !running("hyprpaper") {
                let _ = Command::new("hyprpaper")
                    .args(["--config", string(&root().join("hypr/hyprpaper.conf"))])
                    .stdout(Stdio::null())
                    .stderr(Stdio::null())
                    .spawn();
                std::thread::sleep(Duration::from_millis(300));
            }
        }
        let mut targets = Vec::new();
        if let Ok(o) = run("hyprctl", &["monitors", "-j"]) {
            if let Ok(Value::Array(a)) = serde_json::from_slice(&o.stdout) {
                targets = a
                    .iter()
                    .filter_map(|m| m["name"].as_str().map(str::to_owned))
                    .collect();
            }
        }
        if !targets.iter().any(|t| t.is_empty()) {
            targets.push(String::new());
        }
        for _ in 0..5 {
            let mut successes = 0;
            for target in &targets {
                if let Ok(o) = run(
                    "hyprctl",
                    &[
                        "hyprpaper",
                        "wallpaper",
                        &format!("{target},{},cover", wall.display()),
                    ],
                ) {
                    if o.status.success()
                        && !format!(
                            "{}{}",
                            String::from_utf8_lossy(&o.stdout),
                            String::from_utf8_lossy(&o.stderr)
                        )
                        .to_lowercase()
                        .contains("error")
                    {
                        successes += 1;
                    }
                }
            }
            if successes > 0 {
                applied = true;
                break;
            }
            std::thread::sleep(Duration::from_millis(100));
        }
    }
    if !applied {
        return Err(error(
            "Wallpaper daemon rejected the change; previous selection retained",
        ));
    }
    let link = state().join("wallpaper.set");
    let old = fs::read_link(&link).ok();
    let temporary = state().join(format!(".wallpaper-{}", std::process::id()));
    symlink(&wall, &temporary)?;
    fs::rename(&temporary, &link)?;
    if let Err(e) = atomic(
        &state().join("current_wallpaper"),
        format!("{}\n", wall.display()),
    ) {
        let _ = fs::remove_file(&link);
        if let Some(old) = old {
            let _ = symlink(old, &link);
        }
        return Err(e);
    }
    if let Err(e) = theme::banner(Some(&wall)) {
        eprintln!("Banner refresh: {e}");
    }
    match theme::generate(&wall) {
        Ok(p) => theme::refresh(&p),
        Err(e) => eprintln!("Wallpaper applied, but theme refresh failed: {e}"),
    }
    let _ = run("pkill", &["-RTMIN+19", "-u", &uid(), "-x", "waybar"]);
    let _ = run(
        "notify-send",
        &[
            "-a",
            "minimal",
            "-t",
            "1500",
            "--",
            "Wallpaper Applied",
            wall.file_name().unwrap().to_str().unwrap_or("Wallpaper"),
        ],
    );
    Ok(())
}
pub fn main(args: &[String]) -> Result {
    let command = args.first().map(String::as_str).unwrap_or("");
    if command == "--apply" {
        return apply(
            Path::new(args.get(1).ok_or("Missing image")?),
            args.get(2).map(String::as_str).unwrap_or("0.5"),
            args.get(3).map(String::as_str).unwrap_or("0.5"),
        );
    }
    if !command.is_empty() && !command.starts_with('-') {
        return apply(Path::new(command), "0.5", "0.5");
    }
    let items = discover();
    if command == "--list" {
        println!(
            "{}",
            json!(items
                .iter()
                .map(|i| json!({"path":i.path,"category":i.category,"stem":i.stem}))
                .collect::<Vec<_>>())
        );
        return Ok(());
    }
    if items.is_empty() {
        return Err(error("No wallpapers found"));
    }
    match command {
        "--menu" | "--carousel" => {
            let rt = runtime();
            fs::create_dir_all(&rt)?;
            let meta = fs::symlink_metadata(&rt)?;
            if meta.file_type().is_symlink() || meta.uid() != unsafe { libc::geteuid() } {
                return Err(error("Unsafe runtime directory"));
            }
            fs::set_permissions(&rt, fs::Permissions::from_mode(0o700))?;
            let Some(_guard) = lock(&rt.join("carousel.lock"), true)? else {
                return Ok(());
            };
            let picker = root().join("build/minimal-carousel");
            if picker.is_file()
                && (env::var_os("WAYLAND_DISPLAY").is_some() || env::var_os("DISPLAY").is_some())
            {
                let status = Command::new(picker).env("MINIMAL_ROOT", root()).status()?;
                if status.success() {
                    return Ok(());
                }
                return Err(error("Carousel failed to launch"));
            }
            Err(error(
                "Carousel binary not found or graphical display unavailable",
            ))
        }
        "--random" => {
            use std::io::Read;
            let mut b = [0; 8];
            fs::File::open("/dev/urandom")?.read_exact(&mut b)?;
            apply(
                &items[u64::from_ne_bytes(b) as usize % items.len()].path,
                "0.5",
                "0.5",
            )
        }
        "" => {
            let saved = PathBuf::from(text(&state().join("current_wallpaper")));
            apply(
                if saved.is_file() {
                    &saved
                } else {
                    &items[0].path
                },
                "0.5",
                "0.5",
            )
        }
        _ => Err(error("Unknown wallpaper option")),
    }
}
