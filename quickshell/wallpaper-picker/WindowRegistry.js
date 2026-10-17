.pragma library

// Qt sizes are logical pixels. Only userScale and available logical space
// affect layout; applying compositor DPI again would double-scale the popup.
function applyDpi(baseScale, dpiScale) { return baseScale; }

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
