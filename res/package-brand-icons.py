from pathlib import Path

from PIL import Image


RES = Path(__file__).resolve().parent
BUILD = RES / ".icon-build"
ROOT = RES.parent
SIZES = (16, 24, 32, 48, 64, 128, 256)
CAPTION_SIZES = (16, 20, 24, 32, 40, 48)


def rgba(path: Path) -> Image.Image:
    with Image.open(path) as image:
        return image.convert("RGBA")


def save_ico(prefix: str, output: Path, sizes: tuple[int, ...] = SIZES) -> None:
    frames = [rgba(BUILD / f"{prefix}-{size}.png") for size in sizes]
    largest = frames[-1]
    largest.save(
        output,
        format="ICO",
        sizes=[(size, size) for size in sizes],
        append_images=frames[:-1],
    )


save_ico("app", RES / "icon.ico")
save_ico("app", ROOT / "flutter" / "windows" / "runner" / "resources" / "app_icon.ico")
save_ico("app", ROOT / "flutter" / "assets" / "icon.ico")
save_ico("tray", RES / "tray-icon.ico")
save_ico(
    "caption",
    ROOT / "flutter" / "windows" / "runner" / "resources" / "app_icon_small.ico",
    CAPTION_SIZES,
)
save_ico("caption", ROOT / "flutter" / "assets" / "caption-icon.ico", CAPTION_SIZES)

mac_source = rgba(BUILD / "app-1024.png")
mac_source.save(
    ROOT / "flutter" / "macos" / "Runner" / "AppIcon.icns",
    format="ICNS",
)
