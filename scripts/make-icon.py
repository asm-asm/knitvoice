# 仮のアプリアイコン（1024x1024、透過なし）を作る。
# 使い方: python scripts/make-icon.py  → App/Assets.xcassets と Watch/Assets.xcassets の AppIcon に書き出す
import math
from pathlib import Path

from PIL import Image, ImageDraw

SIZE = 1024
SCALE = 4  # 縁をなめらかにするため大きく描いて縮小する
S = SIZE * SCALE


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def make_icon() -> Image.Image:
    # 背景：上から下へ、あたたかいピンク → くすんだオレンジ
    top, bottom = (244, 143, 151), (238, 170, 110)
    image = Image.new("RGB", (S, S))
    draw = ImageDraw.Draw(image)
    for y in range(S):
        draw.line([(0, y), (S, y)], fill=lerp(top, bottom, y / S))

    # 毛糸玉
    cx, cy, r = S * 0.44, S * 0.56, S * 0.27
    ball, line = (255, 248, 240), (232, 120, 118)
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=ball)
    width = round(S * 0.018)
    # 斜めの巻き線（円の内側だけに描く）
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
    strands = Image.new("RGB", (S, S), ball)
    sd = ImageDraw.Draw(strands)
    for i in range(-4, 5):
        offset = i * r * 0.32
        sd.arc([cx - r * 1.6 + offset, cy - r * 1.1, cx + r * 0.4 + offset, cy + r * 1.3], 200, 340, fill=line, width=width)
    for i in range(-2, 3):
        offset = i * r * 0.35
        sd.arc([cx - r * 0.9, cy - r * 1.8 + offset, cx + r * 1.4, cy + r * 0.6 + offset], 20, 160, fill=line, width=width)
    image.paste(strands, (0, 0), mask)

    # ほどけた糸
    # ほどけた糸（下から右へゆるく波打つ）
    points = []
    for i in range(61):
        t = i / 60
        x = cx + r * 0.2 + t * S * 0.45
        y = cy + r * 0.98 + math.sin(t * math.pi * 2.2) * S * 0.035 + t * S * 0.02
        points.append((x, y))
    draw.line(points, fill=ball, width=round(S * 0.022), joint="curve")

    # 声の波（右上）
    wx, wy = S * 0.70, S * 0.30
    for k, rad in enumerate([0.07, 0.13, 0.19]):
        rr = S * rad
        draw.arc([wx - rr, wy - rr, wx + rr, wy + rr], -50, 50, fill=(255, 255, 255), width=round(S * 0.028))
    dot = S * 0.035
    draw.ellipse([wx - dot, wy - dot, wx + dot, wy + dot], fill=(255, 255, 255))

    return image.resize((SIZE, SIZE), Image.LANCZOS)


CONTENTS = """{
  "images" : [
    {
      "filename" : "icon-1024.png",
      "idiom" : "universal",
      "platform" : "%s",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""

CATALOG = """{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""

if __name__ == "__main__":
    root = Path(__file__).resolve().parent.parent
    icon = make_icon()
    for folder, platform in [("App", "ios"), ("Watch", "watchos")]:
        catalog = root / folder / "Assets.xcassets"
        iconset = catalog / "AppIcon.appiconset"
        iconset.mkdir(parents=True, exist_ok=True)
        (catalog / "Contents.json").write_text(CATALOG, encoding="utf-8")
        (iconset / "Contents.json").write_text(CONTENTS % platform, encoding="utf-8")
        icon.save(iconset / "icon-1024.png")
        print(f"書き出しました: {iconset / 'icon-1024.png'}")
