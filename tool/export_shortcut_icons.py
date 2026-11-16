"""从 Android mdpi 源图生成快捷方式图标的其他像素密度。"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1] / "android/app/src/main/res"
DENSITIES = {"hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
NAMES = ("ic_shortcut_download.png", "ic_shortcut_search.png")


def main():
    for theme in ("", "-night"):
        for name in NAMES:
            with Image.open(ROOT / f"drawable{theme}-mdpi" / name) as source:
                for density, scale in DENSITIES.items():
                    output = ROOT / f"drawable{theme}-{density}" / name
                    output.parent.mkdir(parents=True, exist_ok=True)
                    size = tuple(round(side * scale) for side in source.size)
                    source.resize(size, Image.Resampling.LANCZOS).save(output, optimize=True)
    print("快捷方式图标已生成（hdpi、xhdpi、xxhdpi、xxxhdpi，日间及夜间）。")


if __name__ == "__main__":
    main()
