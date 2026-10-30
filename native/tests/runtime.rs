use base64::{engine::general_purpose::STANDARD, Engine};
use std::{
    env, fs,
    os::unix::fs::{symlink, PermissionsExt},
    path::{Path, PathBuf},
    process::{Command, Output},
    sync::atomic::{AtomicUsize, Ordering},
};
static ID: AtomicUsize = AtomicUsize::new(0);
struct Fixture {
    base: PathBuf,
    root: PathBuf,
}
impl Fixture {
    fn new() -> Self {
        let base = env::temp_dir().join(format!(
            "minimal-native-integration-{}-{}",
            std::process::id(),
            ID.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir_all(base.join("bin")).unwrap();
        fs::create_dir_all(base.join("home")).unwrap();
        fs::create_dir_all(base.join("state/minimal")).unwrap();
        let root = Path::new(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .unwrap()
            .to_path_buf();
        Self { base, root }
    }
    fn command(&self, args: &[&str]) -> Command {
        let mut c = Command::new(env!("CARGO_BIN_EXE_minimal"));
        c.args(args)
            .env("MINIMAL_ROOT", &self.root)
            .env("HOME", self.base.join("home"))
            .env("XDG_STATE_HOME", self.base.join("state"))
            .env("XDG_CONFIG_HOME", self.base.join("config"))
            .env("XDG_CACHE_HOME", self.base.join("cache"))
            .env("XDG_DATA_HOME", self.base.join("data"))
            .env("XDG_RUNTIME_DIR", self.base.join("runtime"))
            .env("TEST_BASE", &self.base)
            .env(
                "PATH",
                format!(
                    "{}:{}",
                    self.base.join("bin").display(),
                    env::var("PATH").unwrap()
                ),
            )
            .env_remove("HYPRLAND_CONFIG");
        c
    }
    fn run(&self, args: &[&str]) -> Output {
        self.command(args).output().unwrap()
    }
    fn stub(&self, name: &str, body: &str) {
        let p = self.base.join("bin").join(name);
        fs::write(&p, format!("#!/bin/sh\n{body}\n")).unwrap();
        fs::set_permissions(p, fs::Permissions::from_mode(0o755)).unwrap();
    }
    fn image(&self) -> PathBuf {
        let p = self.base.join("wall with spaces.png");
        image::RgbImage::from_pixel(16, 16, image::Rgb([60, 90, 160]))
            .save(&p)
            .unwrap();
        p
    }
    fn fake_desktop(&self) {
        for name in ["notify-send", "pkill", "gsettings", "makoctl", "waybar"] {
            self.stub(name, "exit 0");
        }
        self.stub(
            "pgrep",
            "case \"$*\" in *hyprpaper*) exit 0;; *) exit 1;; esac",
        );
        self.stub("systemctl", "exit 99");
        self.stub("hyprctl","case \"$1\" in monitors) printf '[{\"name\":\"TEST\",\"width\":100,\"height\":100}]';; *) echo ok;; esac");
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.base);
    }
}
fn success(o: Output) -> Output {
    assert!(o.status.success(), "{}", String::from_utf8_lossy(&o.stderr));
    o
}
#[test]
fn bar_render_preserves_source_and_resolves_includes() {
    let f = Fixture::new();
    let before = fs::read(f.root.join("waybar/config.jsonc")).unwrap();
    success(f.run(&["bar", "render"]));
    let data: serde_json::Value =
        serde_json::from_slice(&fs::read(f.base.join("state/minimal/waybar.json")).unwrap())
            .unwrap();
    assert!(data.get("include").is_none());
    assert_eq!(data["height"], 38);
    assert_eq!(
        before,
        fs::read(f.root.join("waybar/config.jsonc")).unwrap()
    );
}
#[test]
fn clipboard_binary_copy() {
    let f = Fixture::new();
    let bytes = b"\x89PNG\0\xff\n\0";
    fs::write(f.base.join("decoded"), bytes).unwrap();
    f.stub("cliphist","case \"$1\" in decode) cat > \"$TEST_BASE/row\"; cat \"$TEST_BASE/decoded\";; *) exit 1;; esac");
    f.stub("wl-copy", "cat > \"$TEST_BASE/copied\"");
    let o = f
        .command(&["clipboard-mode"])
        .env("ROFI_RETV", "1")
        .env("ROFI_INFO", STANDARD.encode(b"7\timage"))
        .output()
        .unwrap();
    success(o);
    assert_eq!(fs::read(f.base.join("copied")).unwrap(), bytes);
    assert_eq!(fs::read(f.base.join("row")).unwrap(), b"7\timage\n");
}
#[test]
fn clipboard_delete_refreshes_and_sanitizes_metadata() {
    let f = Fixture::new();
    f.stub("cliphist","case \"$1\" in delete) cat > \"$TEST_BASE/deleted\";; list) printf '8\tvalue\\001injected\n';; esac");
    let o = success(
        f.command(&["clipboard-mode"])
            .env("ROFI_RETV", "10")
            .env("ROFI_INFO", STANDARD.encode(b"7\tclip"))
            .output()
            .unwrap(),
    );
    assert_eq!(fs::read(f.base.join("deleted")).unwrap(), b"7\tclip\n");
    assert!(String::from_utf8_lossy(&o.stdout).contains("value injected"));
}
#[test]
fn clipboard_confirmation_cancel_does_not_wipe() {
    let f = Fixture::new();
    f.stub(
        "cliphist",
        "case \"$1\" in wipe) touch \"$TEST_BASE/wiped\";; list) :;; esac",
    );
    success(
        f.command(&["clipboard-mode"])
            .env("ROFI_RETV", "1")
            .env("ROFI_DATA", "confirm")
            .env("ROFI_INFO", "cancel")
            .output()
            .unwrap(),
    );
    assert!(!f.base.join("wiped").exists());
    success(
        f.command(&["clipboard-mode"])
            .env("ROFI_RETV", "1")
            .env("ROFI_DATA", "confirm")
            .env("ROFI_INFO", "wipe")
            .output()
            .unwrap(),
    );
    assert!(f.base.join("wiped").exists());
}
#[test]
fn wallpaper_rejection_keeps_selection() {
    let f = Fixture::new();
    f.fake_desktop();
    f.stub("hyprctl", "echo 'error: refused'");
    let wall = f.image();
    let marker = f.base.join("state/minimal/current_wallpaper");
    fs::write(&marker, "previous").unwrap();
    let o = f.run(&["wallpaper", "--apply", wall.to_str().unwrap()]);
    assert!(!o.status.success());
    assert_eq!(fs::read_to_string(marker).unwrap(), "previous");
    assert!(!f.base.join("state/minimal/wallpaper.set").exists());
}
#[test]
fn wallpaper_commit_generates_theme_and_cache() {
    let f = Fixture::new();
    f.fake_desktop();
    let wall = f.image();
    success(f.run(&["wallpaper", "--apply", wall.to_str().unwrap()]));
    assert_eq!(
        fs::read_link(f.base.join("state/minimal/wallpaper.set")).unwrap(),
        wall
    );
    for name in [
        "rofi.rasi",
        "waybar.css",
        "foot.ini",
        "hyprlock.conf",
        "palette.json",
        "colors.lua",
        "borders.lua",
        "mako.conf",
        "wlogout.css",
    ] {
        assert!(
            f.base.join("state/minimal/theme").join(name).is_file(),
            "{name}"
        );
    }
    assert!(f.base.join("cache/minimal/wall.quad").is_file());
}
#[test]
fn invalid_image_preserves_theme() {
    let f = Fixture::new();
    let wall = f.image();
    success(f.run(&["theme", wall.to_str().unwrap(), "--generate-only"]));
    let path = f.base.join("state/minimal/theme/palette.json");
    let before = fs::read(&path).unwrap();
    fs::write(&wall, "broken").unwrap();
    assert!(!f
        .run(&["theme", wall.to_str().unwrap(), "--generate-only"])
        .status
        .success());
    assert_eq!(before, fs::read(path).unwrap());
}
#[test]
fn discovery_preserves_namesakes_and_deduplicates_symlinks() {
    let f = Fixture::new();
    for folder in [
        "home/Pictures/Wallpapers/One",
        "home/Documents/Wallpapers/Two",
    ] {
        fs::create_dir_all(f.base.join(folder)).unwrap();
        fs::write(f.base.join(folder).join("same.png"), "x").unwrap();
    }
    symlink(
        f.base.join("home/Pictures/Wallpapers/One/same.png"),
        f.base.join("home/Pictures/Wallpapers/One/link.png"),
    )
    .unwrap();
    let o = success(f.run(&["wallpaper", "--list"]));
    let items: serde_json::Value = serde_json::from_slice(&o.stdout).unwrap();
    let ours: Vec<_> = items
        .as_array()
        .unwrap()
        .iter()
        .filter(|i| {
            i["path"]
                .as_str()
                .unwrap()
                .starts_with(f.base.to_str().unwrap())
        })
        .collect();
    assert_eq!(ours.len(), 2);
}
#[test]
fn install_dry_run_does_not_create_config() {
    let f = Fixture::new();
    success(f.run(&["install", "--dry-run", "--no-tui", "--skip-packages"]));
    assert!(!f.base.join("config").exists());
    assert!(!f.base.join("state/minimal/latest_backup").exists());
}
#[test]
fn standalone_restore_needs_no_checkout() {
    let f = Fixture::new();
    fs::create_dir_all(f.base.join("config/foot")).unwrap();
    fs::write(f.base.join("config/foot/original"), "keep").unwrap();
    success(f.run(&["install", "--skip-packages", "--yes"]));
    let snapshot = fs::read_to_string(f.base.join("state/minimal/latest_backup")).unwrap();
    let o = Command::new(Path::new(snapshot.trim()).join("minimal"))
        .args(["install", "--restore", snapshot.trim()])
        .env("HOME", f.base.join("home"))
        .env("XDG_STATE_HOME", f.base.join("state"))
        .env("MINIMAL_ROOT", "/does/not/exist")
        .output()
        .unwrap();
    success(o);
    assert_eq!(
        fs::read_to_string(f.base.join("config/foot/original")).unwrap(),
        "keep"
    );
    assert!(!f.base.join("config/hypr").exists());
}
#[test]
fn thumbnail_has_requested_dimensions() {
    let f = Fixture::new();
    let image = f.image();
    let out = f.base.join("thumb.png");
    success(f.run(&[
        "thumbnail",
        image.to_str().unwrap(),
        out.to_str().unwrap(),
        "240",
        "680",
    ]));
    assert_eq!(image::image_dimensions(out).unwrap(), (240, 680));
}
#[test]
fn image_paths_are_json_escaped() {
    let f = Fixture::new();
    let o = success(
        f.command(&["rofi-images", "clipboard"])
            .env("XDG_CACHE_HOME", f.base.join("quote\"dir"))
            .output()
            .unwrap(),
    );
    assert!(String::from_utf8_lossy(&o.stdout).contains("quote\\\"dir"));
}

#[test]
fn brightness_failure_has_no_success_notification() {
    let f = Fixture::new();
    f.stub("brightnessctl", "exit 1");
    f.stub(
        "notify-send",
        "printf '%s\\n' \"$@\" > \"$TEST_BASE/notified\"",
    );
    let o = Command::new(f.root.join("scripts/brightness.sh"))
        .arg("--dec")
        .env(
            "PATH",
            format!(
                "{}:{}",
                f.base.join("bin").display(),
                env::var("PATH").unwrap()
            ),
        )
        .env("TEST_BASE", &f.base)
        .output()
        .unwrap();
    assert!(!o.status.success());
    let notification = fs::read_to_string(f.base.join("notified")).unwrap();
    assert!(notification.contains("Brightness adjustment failed"));
    assert!(!notification.contains("int:value:"));
}
#[test]
fn power_menu_cleans_temporary_files() {
    let f = Fixture::new();
    f.stub("pgrep", "exit 1");
    f.stub(
        "wlogout",
        "printf '%s\\n' \"$@\" > \"$TEST_BASE/power-args\"",
    );
    let o = Command::new(f.root.join("scripts/powermenu.sh"))
        .env("MINIMAL_ROOT", &f.root)
        .env(
            "PATH",
            format!(
                "{}:{}",
                f.base.join("bin").display(),
                env::var("PATH").unwrap()
            ),
        )
        .env("TEST_BASE", &f.base)
        .env("XDG_STATE_HOME", f.base.join("state"))
        .output()
        .unwrap();
    success(o);
    let args = fs::read_to_string(f.base.join("power-args")).unwrap();
    let lines: Vec<_> = args.lines().collect();
    for flag in ["--layout", "--css"] {
        let i = lines.iter().position(|s| *s == flag).unwrap();
        assert!(!Path::new(lines[i + 1]).exists());
    }
}
#[test]
fn update_failure_is_distinct_from_no_updates() {
    let f = Fixture::new();
    let run = || {
        Command::new(f.root.join("scripts/updates.sh"))
            .env(
                "PATH",
                format!(
                    "{}:{}",
                    f.base.join("bin").display(),
                    env::var("PATH").unwrap()
                ),
            )
            .output()
            .unwrap()
    };
    f.stub("checkupdates", "exit 1");
    let failed: serde_json::Value = serde_json::from_slice(&success(run()).stdout).unwrap();
    assert_eq!(failed["class"], "unavailable");
    f.stub("checkupdates", "exit 2");
    let empty: serde_json::Value = serde_json::from_slice(&success(run()).stdout).unwrap();
    assert_eq!(empty["text"], "");
}
#[test]
fn concurrent_wallpaper_changes_leave_consistent_selection() {
    let f = Fixture::new();
    f.fake_desktop();
    let one = f.image();
    let two = f.base.join("second.png");
    image::RgbImage::from_pixel(16, 16, image::Rgb([180, 60, 60]))
        .save(&two)
        .unwrap();
    let mut a = f
        .command(&["wallpaper", "--apply", one.to_str().unwrap()])
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .spawn()
        .unwrap();
    let mut b = f
        .command(&["wallpaper", "--apply", two.to_str().unwrap()])
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .spawn()
        .unwrap();
    assert!(a.wait().unwrap().success());
    assert!(b.wait().unwrap().success());
    let selected = fs::read_to_string(f.base.join("state/minimal/current_wallpaper")).unwrap();
    let link = fs::read_link(f.base.join("state/minimal/wallpaper.set")).unwrap();
    let palette: serde_json::Value =
        serde_json::from_slice(&fs::read(f.base.join("state/minimal/theme/palette.json")).unwrap())
            .unwrap();
    assert_eq!(Path::new(selected.trim()), link);
    assert_eq!(palette["wallpaper"].as_str().unwrap(), selected.trim());
}
#[test]
fn picker_rejects_symlinked_runtime_lock() {
    let f = Fixture::new();
    fs::create_dir_all(f.base.join("runtime/minimal")).unwrap();
    let target = f.base.join("untouched");
    fs::write(&target, "keep").unwrap();
    symlink(&target, f.base.join("runtime/minimal/carousel.lock")).unwrap();
    assert!(!f.run(&["wallpaper", "--menu"]).status.success());
    assert_eq!(fs::read_to_string(target).unwrap(), "keep");
}
