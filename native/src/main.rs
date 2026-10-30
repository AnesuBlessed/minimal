mod config;
mod desktop;
mod install;
mod theme;
mod wallpaper;

use std::{
    env, fs,
    io::{self, Write},
    path::{Path, PathBuf},
    process::{Command, Output, Stdio},
};
type Result<T = ()> = std::result::Result<T, Box<dyn std::error::Error>>;
fn error(s: impl Into<String>) -> Box<dyn std::error::Error> {
    io::Error::other(s.into()).into()
}
fn home() -> PathBuf {
    PathBuf::from(env::var_os("HOME").expect("HOME must be set"))
}
fn xdg(key: &str, fallback: &str) -> PathBuf {
    env::var_os(key)
        .filter(|s| !s.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| home().join(fallback))
}
fn state() -> PathBuf {
    xdg("XDG_STATE_HOME", ".local/state").join("minimal")
}
fn cache() -> PathBuf {
    xdg("XDG_CACHE_HOME", ".cache").join("minimal")
}
fn runtime() -> PathBuf {
    env::var_os("XDG_RUNTIME_DIR")
        .filter(|s| !s.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| cache().join("runtime"))
        .join("minimal")
}
fn root() -> PathBuf {
    env::var_os("MINIMAL_ROOT")
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            PathBuf::from(env!("CARGO_MANIFEST_DIR"))
                .parent()
                .unwrap()
                .to_path_buf()
        })
}
fn atomic(path: &Path, contents: impl AsRef<[u8]>) -> Result {
    fs::create_dir_all(path.parent().ok_or("Missing parent")?)?;
    let temp = path.with_extension(format!("tmp-{}", std::process::id()));
    let result = (|| {
        fs::write(&temp, contents)?;
        fs::rename(&temp, path)?;
        Ok(())
    })();
    if result.is_err() {
        let _ = fs::remove_file(temp);
    }
    result
}
fn run(program: &str, args: &[&str]) -> Result<Output> {
    Ok(Command::new(program).args(args).output()?)
}
fn checked(program: &str, args: &[&str]) -> Result<Output> {
    let o = run(program, args)?;
    if !o.status.success() {
        return Err(error(format!(
            "{program}: {}",
            String::from_utf8_lossy(&o.stderr)
        )));
    }
    Ok(o)
}
fn input(program: &str, args: &[&str], bytes: &[u8]) -> Result<Output> {
    let mut child = Command::new(program)
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()?;
    // Drain output concurrently: a large clipboard decode must not deadlock on a full pipe.
    let mut stdin = child.stdin.take().unwrap();
    let data = bytes.to_vec();
    let writer = std::thread::spawn(move || stdin.write_all(&data));
    let output = child.wait_with_output()?;
    let written = writer.join().map_err(|_| error("stdin writer failed"))?;
    if !output.status.success() {
        return Err(error(format!(
            "{program}: {}",
            String::from_utf8_lossy(&output.stderr)
        )));
    }
    written?;
    Ok(output)
}
fn exists(program: &str) -> bool {
    use std::os::unix::fs::PermissionsExt;
    env::split_paths(&env::var_os("PATH").unwrap_or_default()).any(|d| {
        fs::metadata(d.join(program))
            .is_ok_and(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
    })
}
fn text(path: &Path) -> String {
    fs::read_to_string(path)
        .unwrap_or_default()
        .trim()
        .to_owned()
}
fn string(path: &Path) -> &str {
    path.to_str().expect("Path must be UTF-8")
}
fn uid() -> String {
    unsafe { libc::geteuid() }.to_string()
}
fn lock(path: &Path, nonblock: bool) -> Result<Option<fs::File>> {
    use std::os::{fd::AsRawFd, unix::fs::OpenOptionsExt};
    fs::create_dir_all(path.parent().ok_or("Missing lock parent")?)?;
    let f = fs::OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .mode(0o600)
        .custom_flags(libc::O_NOFOLLOW | libc::O_CLOEXEC)
        .open(path)?;
    if unsafe {
        libc::flock(
            f.as_raw_fd(),
            libc::LOCK_EX | if nonblock { libc::LOCK_NB } else { 0 },
        )
    } != 0
    {
        let e = io::Error::last_os_error();
        if nonblock && e.kind() == io::ErrorKind::WouldBlock {
            return Ok(None);
        }
        return Err(e.into());
    }
    Ok(Some(f))
}
fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    if let Err(e) = dispatch(&args) {
        eprintln!("Minimal: {e}");
        std::process::exit(1);
    }
}
fn dispatch(args: &[String]) -> Result {
    let (cmd, args) = args.split_first().ok_or("Expected a subcommand")?;
    match cmd.as_str() {
        "bar" => desktop::bar(args),
        "wallpaper" => wallpaper::main(args),
        "theme" => theme::main(args),
        "banner" => theme::banner(args.first().map(Path::new)),
        "thumbnail" => theme::thumbnail(args),
        "rofi-images" => {
            print!(
                "{}",
                desktop::rofi_images(args.first().map(String::as_str).unwrap_or("launcher"))
            );
            Ok(())
        }
        "clipboard-placement" => desktop::placement(),
        "clipboard-mode" => desktop::clipboard(),
        "terminal" => desktop::terminal(args),
        "power-files" => desktop::power_files(args),
        "install" => install::main(args),
        "check" => config::check(),
        _ => Err(error(format!("Unknown command: {cmd}"))),
    }
}
