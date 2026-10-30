use crate::*;
use image::{imageops::FilterType, DynamicImage, ImageDecoder, ImageReader};
use serde_json::json;
use std::collections::BTreeMap;
pub type Palette = BTreeMap<String, String>;
pub fn load(path: &Path) -> Result<DynamicImage> {
    let mut decoder = ImageReader::open(path)?
        .with_guessed_format()?
        .into_decoder()?;
    let orientation = decoder.orientation()?;
    let mut image = DynamicImage::from_decoder(decoder)?;
    image.apply_orientation(orientation);
    Ok(image)
}
fn hsv(rgb: [f64; 3]) -> (f64, f64, f64) {
    let [r, g, b] = rgb;
    let max = r.max(g).max(b);
    let min = r.min(g).min(b);
    let delta = max - min;
    let h = if delta == 0.0 {
        0.0
    } else if max == r {
        ((g - b) / delta).rem_euclid(6.0) / 6.0
    } else if max == g {
        ((b - r) / delta + 2.0) / 6.0
    } else {
        ((r - g) / delta + 4.0) / 6.0
    };
    (h, if max == 0.0 { 0.0 } else { delta / max }, max)
}
fn hls(h: f64, l: f64, s: f64) -> String {
    let a = s * l.min(1.0 - l);
    let f = |n: f64| {
        let k = (n + h * 12.0) % 12.0;
        ((l - a * (-1.0f64).max((k - 3.0).min(9.0 - k).min(1.0))) * 255.0).round() as u8
    };
    format!("{:02x}{:02x}{:02x}", f(0.0), f(8.0), f(4.0))
}
pub fn palette(image: &DynamicImage) -> Palette {
    let thumb = image.thumbnail(128, 128).to_rgb8();
    let mut bins = BTreeMap::<u16, (u64, [u64; 3])>::new();
    for p in thumb.pixels() {
        let k = ((p[0] as u16 >> 4) << 8) | ((p[1] as u16 >> 4) << 4) | (p[2] as u16 >> 4);
        let e = bins.entry(k).or_default();
        e.0 += 1;
        for i in 0..3 {
            e.1[i] += p[i] as u64;
        }
    }
    let mut chosen = (0.0, 0.0);
    let mut best = -1.0;
    for (_, (n, sum)) in bins {
        let (h, s, v) = hsv(sum.map(|x| x as f64 / n as f64 / 255.0));
        let score = n as f64 * (0.15 + s) * (0.3 + v.min(1.0 - v));
        if score > best {
            best = score;
            chosen = (h, if s < 0.1 { 0.0 } else { s.min(0.72) });
        }
    }
    [
        ("background", 0.09, 0.35),
        ("surface", 0.14, 0.4),
        ("foreground", 0.92, 0.25),
        ("muted", 0.68, 0.3),
        ("accent", 0.72, 1.0),
        ("secondary", 0.57, 0.65),
        ("border", 0.34, 0.45),
        ("selection", 0.28, 0.65),
    ]
    .into_iter()
    .map(|(k, l, s)| (k.into(), hls(chosen.0, l, chosen.1 * s)))
    .collect()
}
fn rgba(hex: &str, alpha: &str) -> String {
    format!(
        "rgba({},{},{},{alpha})",
        u8::from_str_radix(&hex[0..2], 16).unwrap(),
        u8::from_str_radix(&hex[2..4], 16).unwrap(),
        u8::from_str_radix(&hex[4..6], 16).unwrap()
    )
}
pub fn generate(wall: &Path) -> Result<Palette> {
    let p = palette(&load(wall)?);
    let dir = state().join("theme");
    let bg = &p["background"];
    let fg = &p["foreground"];
    let accent = &p["accent"];
    let mut files = BTreeMap::<&str, String>::new();
    files.insert("waybar.css",format!("@define-color bar-bg transparent;\n@define-color main-bg {};\n@define-color main-fg #{fg};\n@define-color active-bg #{accent};\n@define-color active-fg #{bg};\n@define-color hover-bg #{};\n@define-color hover-fg #{fg};\n",rgba(bg,".88"),p["selection"]));
    files.insert("rofi.rasi",format!("* {{\n main-bg: #{bg}eb;\n main-fg: #{fg};\n main-br: #{};\n main-ex: #{}ee;\n select-bg: #{accent};\n select-fg: #{bg};\n}}\n",p["border"],p["surface"]));
    files.insert("colors.lua",format!("return {{ accent = \"rgba({accent}ff)\", accent_subtle = \"rgba({}cc)\", border_dark = \"rgba({}cc)\", bg_dark = \"0x{bg}\", text_main = \"0x{fg}\" }}\n",p["secondary"],p["border"]));
    files.insert("borders.lua",format!("hl.config({{ general = {{ col = {{ active_border = {{ colors = {{ \"rgba({accent}ff)\", \"rgba({}cc)\" }}, angle = 45 }}, inactive_border = \"rgba({}cc)\" }} }} }})\n",p["secondary"],p["border"]));
    for (output, source) in [
        ("mako.conf", "mako/config"),
        ("hyprlock.conf", "hypr/hyprlock.conf"),
        ("foot.ini", "foot/foot.ini"),
        ("wlogout.css", "wlogout/style.css"),
    ] {
        let template = fs::read_to_string(root().join(source))?;
        let replacements = [
            ("0f1a2a", bg),
            ("182234", &p["surface"]),
            ("cce1ff", fg),
            ("506182", &p["border"]),
            ("7a92c2", &p["muted"]),
            ("ca9ee6", accent),
            ("aac7f0", &p["secondary"]),
            ("3a4e6b", &p["selection"]),
        ];
        // One pass avoids replacing a generated value that matches another template token.
        let mut s = String::new();
        let mut i = 0;
        while i < template.len() {
            if let Some((old, new)) = replacements.iter().find(|(old, _)| {
                template
                    .get(i..i + old.len())
                    .is_some_and(|s| s.eq_ignore_ascii_case(old))
            }) {
                s.push_str(new);
                i += old.len();
            } else {
                let c = template[i..].chars().next().unwrap();
                s.push(c);
                i += c.len_utf8();
            }
        }
        if output == "wlogout.css" {
            s = s.replace("rgba(15, 26, 42, 0.85)", &rgba(bg, ".85"));
        }
        files.insert(output, s);
    }
    let mut metadata = json!(p);
    metadata["wallpaper"] = json!(wall.canonicalize()?);
    files.insert("palette.json", serde_json::to_string_pretty(&metadata)?);
    for (name, s) in files {
        atomic(&dir.join(name), s)?;
    }
    Ok(p)
}
pub fn refresh(p: &Palette) {
    let dir = state().join("theme");
    let _ = run("hyprctl", &["repl", &text(&dir.join("borders.lua"))]);
    let _ = crate::desktop::bar(&["reload".into()]);
    if let Ok(o) = run("pgrep", &["-u", &uid(), "-x", "mako"]) {
        for pid in String::from_utf8_lossy(&o.stdout).split_whitespace() {
            let args = fs::read(format!("/proc/{pid}/cmdline")).unwrap_or_default();
            if args
                .split(|b| *b == 0)
                .any(|a| a == string(&dir.join("mako.conf")).as_bytes())
            {
                let _ = run("makoctl", &["reload"]);
            } else if args
                .split(|b| *b == 0)
                .any(|a| a == string(&root().join("mako/config")).as_bytes())
            {
                if let Ok(pid) = pid.parse::<i32>() {
                    unsafe {
                        libc::kill(pid, libc::SIGTERM);
                    }
                }
                let _ = Command::new("mako")
                    .arg("--config")
                    .arg(dir.join("mako.conf"))
                    .stdout(Stdio::null())
                    .stderr(Stdio::null())
                    .spawn();
            }
        }
    }
    let rgb = |hex: &str| {
        [0, 2, 4].map(|i| u8::from_str_radix(&hex[i..i + 2], 16).unwrap() as f64 / 255.0)
    };
    let (h, s, _) = hsv(rgb(&p["accent"]));
    let accents = [
        ("blue", "3584e4"),
        ("teal", "2190a4"),
        ("green", "3a944a"),
        ("yellow", "c88800"),
        ("orange", "ed5b00"),
        ("red", "e62d42"),
        ("pink", "d56199"),
        ("purple", "9141ac"),
    ];
    let closest = if s < 0.1 {
        "slate"
    } else {
        accents
            .iter()
            .min_by(|a, b| {
                let distance = |hex| {
                    let d = (hsv(rgb(hex)).0 - h).abs();
                    d.min(1.0 - d)
                };
                distance(a.1).total_cmp(&distance(b.1))
            })
            .unwrap()
            .0
    };
    let _ = run(
        "gsettings",
        &[
            "set",
            "org.gnome.desktop.interface",
            "accent-color",
            closest,
        ],
    );
}
pub fn main(args: &[String]) -> Result {
    if args.first().is_some_and(|a| a == "--rofi") {
        print!(
            "{}",
            fs::read_to_string(state().join("theme/rofi.rasi")).unwrap_or_default()
        );
        return Ok(());
    }
    let wall = args
        .first()
        .cloned()
        .unwrap_or_else(|| text(&state().join("current_wallpaper")));
    let p = generate(Path::new(&wall))?;
    if !args.iter().any(|a| a == "--generate-only") {
        refresh(&p);
    }
    Ok(())
}
fn save(image: &DynamicImage, path: &Path) -> Result {
    let tmp = path.with_extension(format!("tmp-{}", std::process::id()));
    image.save_with_format(&tmp, image::ImageFormat::Png)?;
    fs::rename(tmp, path)?;
    Ok(())
}
pub fn thumbnail(args: &[String]) -> Result {
    if args.len() != 4 {
        return Err(error("thumbnail: source destination width height"));
    }
    let w = args[2].parse::<u32>()?;
    let h = args[3].parse::<u32>()?;
    if w == 0 || h == 0 || w > 4096 || h > 4096 {
        return Err(error("Invalid thumbnail dimensions"));
    }
    let out = Path::new(&args[1]);
    fs::create_dir_all(out.parent().ok_or("Missing thumbnail parent")?)?;
    save(
        &load(Path::new(&args[0]))?.resize_to_fill(w, h, FilterType::Triangle),
        out,
    )
}
pub fn banner(path: Option<&Path>) -> Result {
    let wall = path
        .map(PathBuf::from)
        .or_else(|| {
            let p = PathBuf::from(text(&state().join("current_wallpaper")));
            p.is_file().then_some(p)
        })
        .or_else(|| wallpaper::discover().first().map(|i| i.path.clone()));
    let Some(wall) = wall else {
        return Ok(());
    };
    let wall = wall.canonicalize()?;
    let dir = cache();
    fs::create_dir_all(&dir)?;
    let mut size = (1366, 768);
    if let Ok(o) = run("hyprctl", &["monitors", "-j"]) {
        if let Ok(v) = serde_json::from_slice::<serde_json::Value>(&o.stdout) {
            if let Some(a) = v.as_array() {
                if let Some(m) = a
                    .iter()
                    .find(|m| m["focused"].as_bool() == Some(true))
                    .or_else(|| a.first())
                {
                    size = (
                        m["width"].as_u64().unwrap_or(1366).clamp(1, 16384) as u32,
                        m["height"].as_u64().unwrap_or(768).clamp(1, 16384) as u32,
                    );
                }
            }
        }
    }
    let stamp = format!(
        "{}:{:?}:{}x{}",
        wall.display(),
        fs::metadata(&wall)?.modified()?,
        size.0,
        size.1
    );
    if text(&dir.join("wall.source")) == stamp
        && ["thmb", "blur", "sqre", "quad"]
            .iter()
            .all(|s| dir.join(format!("wall.{s}")).is_file())
    {
        return Ok(());
    }
    let image = load(&wall)?;
    let screen = image.resize_to_fill(size.0.max(960), size.1.max(420), FilterType::Lanczos3);
    let (x, y) = (
        screen.width().saturating_sub(960) / 2,
        screen.height().saturating_sub(420) / 2,
    );
    let tint = |im: DynamicImage, color: [u8; 3], a: f32| {
        let mut rgb = im.to_rgb8();
        for p in rgb.pixels_mut() {
            for i in 0..3 {
                p[i] = (p[i] as f32 * (1.0 - a) + color[i] as f32 * a).round() as u8;
            }
        }
        DynamicImage::ImageRgb8(rgb)
    };
    save(
        &tint(
            screen.crop_imm(x, y, 480, 420),
            [255, 255, 255],
            16.0 / 255.0,
        ),
        &dir.join("wall.thmb"),
    )?;
    save(
        &tint(
            screen.crop_imm(x, y, 56, 420).blur(8.0),
            [15, 26, 42],
            110.0 / 255.0,
        ),
        &dir.join("wall.blur"),
    )?;
    let square = image.resize_to_fill(500, 500, FilterType::Lanczos3);
    save(&square, &dir.join("wall.sqre"))?;
    let mut quad = square.to_rgba8();
    for (x, y, p) in quad.enumerate_pixels_mut() {
        let yf = y as f64;
        if x as f64 >= 450.0 - yf * 0.1 {
            p[3] = 76;
        }
        if x as f64 >= 500.0 - yf * 0.1 {
            p[3] = 0;
        }
    }
    save(&DynamicImage::ImageRgba8(quad), &dir.join("wall.quad"))?;
    atomic(&dir.join("wall.source"), stamp)
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn monochrome_neutral() {
        let p = palette(&DynamicImage::ImageRgb8(image::RgbImage::from_pixel(
            2,
            2,
            image::Rgb([100, 100, 100]),
        )));
        assert_eq!(&p["accent"][0..2], &p["accent"][2..4]);
    }
    #[test]
    fn colored_wall_changes_palette() {
        let im = |rgb| DynamicImage::ImageRgb8(image::RgbImage::from_pixel(2, 2, image::Rgb(rgb)));
        assert_ne!(
            palette(&im([220, 30, 30]))["accent"],
            palette(&im([20, 20, 220]))["accent"]
        );
    }
}
