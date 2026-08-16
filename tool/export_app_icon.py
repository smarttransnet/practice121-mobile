"""Export Option C for Google Play listing + Android launcher densities."""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "store/play/app-icon-source.png"
RES = ROOT / "android/app/src/main/res"
LISTING = ROOT / "store/play/listing"

CONTENT_RATIO = 0.64

# In-app launcher (mipmap) — required on device, not uploaded to Play Console.
LAUNCHER = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}
ADAPTIVE_FG = {
    "mdpi": 108,
    "hdpi": 162,
    "xhdpi": 216,
    "xxhdpi": 324,
    "xxxhdpi": 432,
}


def square(im: Image.Image) -> Image.Image:
    rgba = im.convert("RGBA")
    w, h = rgba.size
    side = min(w, h)
    left = (w - side) // 2
    top = (h - side) // 2
    return rgba.crop((left, top, left + side, top + side))


def sample_corners(im: Image.Image) -> tuple[tuple[int, int, int], tuple[int, int, int]]:
    px = im.load()
    w, h = im.size
    return px[4, 4][:3], px[w - 5, h - 5][:3]


def is_logo_pixel(r: int, g: int, b: int, a: int) -> bool:
    if a < 20:
        return False
    lum = 0.299 * r + 0.587 * g + 0.114 * b
    if lum >= 168:
        return True
    return g >= 150 and r >= 110 and b >= 110 and lum >= 140


def extract_logo(src: Image.Image) -> Image.Image:
    w, h = src.size
    px = src.load()
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    op = out.load()
    xs: list[int] = []
    ys: list[int] = []
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if not is_logo_pixel(r, g, b, a):
                continue
            op[x, y] = (r, g, b, 255)
            xs.append(x)
            ys.append(y)
    if not xs:
        raise RuntimeError("Could not extract mic / P121 from source icon")
    pad = 8
    return out.crop(
        (
            max(min(xs) - pad, 0),
            max(min(ys) - pad, 0),
            min(max(xs) + pad + 1, w),
            min(max(ys) + pad + 1, h),
        )
    )


def make_gradient(width: int, height: int, start: tuple[int, int, int], end: tuple[int, int, int]) -> Image.Image:
    img = Image.new("RGB", (width, height))
    px = img.load()
    denom = max(width + height - 2, 1)
    for y in range(height):
        for x in range(width):
            t = (x + y) / denom
            px[x, y] = (
                int(start[0] + (end[0] - start[0]) * t),
                int(start[1] + (end[1] - start[1]) * t),
                int(start[2] + (end[2] - start[2]) * t),
            )
    return img.convert("RGBA")


def place_logo(canvas: Image.Image, logo: Image.Image, ratio: float) -> Image.Image:
    side = min(canvas.size)
    max_side = int(side * ratio)
    bw, bh = logo.size
    scale = min(max_side / bw, max_side / bh)
    nw, nh = max(1, int(bw * scale)), max(1, int(bh * scale))
    scaled = logo.resize((nw, nh), Image.Resampling.LANCZOS)
    out = canvas.copy()
    out.alpha_composite(scaled, ((canvas.size[0] - nw) // 2, (canvas.size[1] - nh) // 2))
    return out


def save(im: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    im.save(path, format="PNG")
    print(f"wrote {path.relative_to(ROOT)} {im.size} {im.mode}")


def write_gradient_drawable(start: tuple[int, int, int], end: tuple[int, int, int]) -> None:
    def hx(c: tuple[int, int, int]) -> str:
        return f"#{c[0]:02x}{c[1]:02x}{c[2]:02x}"

    (RES / "drawable/ic_launcher_background.xml").write_text(
        f"""<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android">
    <gradient
        android:type="linear"
        android:angle="315"
        android:startColor="{hx(start)}"
        android:endColor="{hx(end)}" />
</shape>
""",
        encoding="utf-8",
    )
    (RES / "values/ic_launcher_background.xml").write_text(
        f"""<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">{hx(start)}</color>
</resources>
""",
        encoding="utf-8",
    )


def make_feature_graphic(logo: Image.Image, start: tuple[int, int, int], end: tuple[int, int, int]) -> Image.Image:
    """Play Console feature graphic: 1024x500, 24-bit PNG, no alpha."""
    w, h = 1024, 500
    graphic = make_gradient(w, h, start, end)
    max_h = int(h * 0.70)
    bw, bh = logo.size
    scale = min(max_h / bh, 280 / bw)
    nw, nh = max(1, int(bw * scale)), max(1, int(bh * scale))
    scaled = logo.resize((nw, nh), Image.Resampling.LANCZOS)
    graphic.alpha_composite(scaled, (72, (h - nh) // 2))

    draw = ImageDraw.Draw(graphic)
    try:
        title_font = ImageFont.truetype("arialbd.ttf", 72)
        sub_font = ImageFont.truetype("arial.ttf", 32)
    except OSError:
        title_font = ImageFont.load_default()
        sub_font = title_font
    text_x = 72 + nw + 48
    draw.text((text_x, 168), "Practice121", fill=(255, 255, 255), font=title_font)
    draw.text(
        (text_x, 268),
        "Clinical voice notes",
        fill=(210, 245, 235),
        font=sub_font,
    )
    return graphic.convert("RGB")


def main() -> None:
    master = 1024
    src = square(Image.open(SRC)).resize((master, master), Image.Resampling.LANCZOS)
    start, end = sample_corners(src)
    logo = extract_logo(src)

    gradient = make_gradient(master, master, start, end)
    full_icon = place_logo(gradient, logo, CONTENT_RATIO)
    fg = place_logo(Image.new("RGBA", (master, master), (0, 0, 0, 0)), logo, CONTENT_RATIO)

    listing = LISTING
    if listing.exists():
        for old in listing.rglob("*"):
            if old.is_file():
                old.unlink()

    # ── Google Play Console uploads ────────────────────────────────────────
    icon_512 = full_icon.resize((512, 512), Image.Resampling.LANCZOS)
    save(icon_512, listing / "01-play-icon-512.png")
    save(icon_512, ROOT / "store/play/icon-512.png")

    feature = make_feature_graphic(logo, start, end)
    feature_path = listing / "02-play-feature-graphic-1024x500.png"
    feature_path.parent.mkdir(parents=True, exist_ok=True)
    feature.save(feature_path, format="PNG")
    print(f"wrote {feature_path.relative_to(ROOT)} {feature.size} {feature.mode}")

    # ── Android launcher densities (bundled in the AAB) ────────────────────
    for density, size in LAUNCHER.items():
        resized = full_icon.resize((size, size), Image.Resampling.LANCZOS)
        save(resized, listing / "android-launcher" / f"launcher-{density}-{size}.png")
        save(resized, RES / f"mipmap-{density}" / "launcher_icon.png")

    for density, size in ADAPTIVE_FG.items():
        resized = fg.resize((size, size), Image.Resampling.LANCZOS)
        save(resized, listing / "android-launcher" / f"adaptive-foreground-{density}-{size}.png")
        save(resized, RES / f"mipmap-{density}" / "launcher_icon_foreground.png")

    write_gradient_drawable(start, end)

    inventory = listing / "SIZES.txt"
    inventory.write_text(
        """Google Play Console (upload these)
---------------------------------
01-play-icon-512.png                  512 x 512    PNG 32-bit (with alpha)   REQUIRED
02-play-feature-graphic-1024x500.png  1024 x 500   PNG 24-bit (no alpha)     REQUIRED

Phone screenshots (not generated — capture from emulator)
---------------------------------------------------------
At least 2 images, each side 320–3840 px, ratio between 1:2 and 2:1
Recommended: 1080 x 1920

Android launcher (already copied into android/app/src/main/res/mipmap-*)
----------------------------------------------------------------------
launcher-mdpi-48.png
launcher-hdpi-72.png
launcher-xhdpi-96.png
launcher-xxhdpi-144.png
launcher-xxxhdpi-192.png
adaptive-foreground-mdpi-108.png
adaptive-foreground-hdpi-162.png
adaptive-foreground-xhdpi-216.png
adaptive-foreground-xxhdpi-324.png
adaptive-foreground-xxxhdpi-432.png
""",
        encoding="utf-8",
    )
    print(f"wrote {inventory.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
