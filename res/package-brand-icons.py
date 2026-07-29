from pathlib import Path

from PIL import Image


RES = Path(__file__).resolve().parent
BUILD = RES / ".icon-build"
ROOT = RES.parent
SIZES = (16, 24, 32, 48, 64, 128, 256)


def rgba(path: Path) -> Image.Image:
    with Image.open(path) as image:
        return image.convert("RGBA")


def save_ico(prefix: str, output: Path) -> None:
    frames = [rgba(BUILD / f"{prefix}-{size}.png") for size in SIZES]
    largest = frames[-1]
    largest.save(
        output,
        format="ICO",
        sizes=[(size, size) for size in SIZES],
        append_images=frames[:-1],
    )


save_ico("app", RES / "icon.ico")
save_ico("app", ROOT / "flutter" / "windows" / "runner" / "resources" / "app_icon.ico")
save_ico("tray", RES / "tray-icon.ico")

mac_source = rgba(BUILD / "app-1024.png")
mac_source.save(
    ROOT / "flutter" / "macos" / "Runner" / "AppIcon.icns",
    format="ICNS",
)
