.pragma library

// dpiScale is the compositor's output scale (Hyprland `scale`, 1.0-3.0).
// The resolution factor below already grows with pixel count, so a raw
// multiply would double-count on HiDPI. We apply it damped (sqrt) and
// clamped, which is what makes the UI read the same physical size on a
// 14" 2560x1600 laptop as on a 24" 1920x1080 monitor.
function applyDpi(baseScale, dpiScale) {
    var d = parseFloat(dpiScale);
    if (!d || isNaN(d) || d <= 0) return baseScale;
    d = Math.min(Math.max(d, 0.5), 3.0);
    return baseScale * Math.sqrt(d);
}

function getScale(mw, mh, userScale, dpiScale) {
    if (arguments.length === 2) {
        userScale = mh;
        mh = mw * (1080.0 / 1920.0);
    }

    if (mw <= 0 || mh <= 0) return 1.0;
    
    let rw = mw / 1920.0;
    let rh = mh / 1080.0;
    let r = Math.min(rw, rh);
    
    let baseScale = 1.0;
    
    if (r <= 1.0) {
        baseScale = Math.max(0.35, Math.pow(r, 0.85));
    } else {
        baseScale = Math.pow(r, 0.5);
    }
    
    return applyDpi(baseScale, dpiScale) * (userScale !== undefined ? userScale : 1.0);
}

function s(val, scale) {
    return Math.round(val * scale);
}

function getLayout(name, mx, my, mw, mh, userScale, dpiScale) {
    let scale = getScale(mw, mh, userScale, dpiScale);

    let base = {
        "wallpaper": { w: mw, h: s(650, scale), rx: 0, ry: Math.floor((mh/2)-(s(650, scale)/2)), comp: "WallpaperPicker.qml" },
        "hidden":    { w: 1, h: 1, rx: -5000 - mx, ry: -5000 - my, comp: "" } 
    };

    if (!base[name]) return null;
    
    let t = base[name];
    t.x = mx + t.rx;
    t.y = my + t.ry;
    
    return t;
}
