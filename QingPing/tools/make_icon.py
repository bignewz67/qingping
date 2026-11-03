"""生成「清屏」App 图标 1024x1024（无透明通道，符合 App Store 要求）。"""

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

SIZE = 1024
OUT = Path(__file__).resolve().parents[1] / "ios" / "Sources" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon-1024.png"

FONT_BOLD = r"C:\Windows\Fonts\msyhbd.ttc"
FONT_LIGHT = r"C:\Windows\Fonts\msyh.ttc"

TOP = (0x11, 0xC9, 0xA6)
BOTTOM = (0x2B, 0x6D, 0xF6)
BADGE = (0x00, 0xB4, 0x94)


def gradient() -> Image.Image:
    y = np.linspace(0, 1, SIZE)[:, None]
    x = np.linspace(0, 1, SIZE)[None, :]
    t = np.clip(x * 0.35 + y * 0.65, 0, 1) ** 0.92

    arr = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    for i in range(3):
        arr[..., i] = TOP[i] + (BOTTOM[i] - TOP[i]) * t

    # 左上角柔光
    dist = np.sqrt((x - 0.16) ** 2 + (y - 0.10) ** 2)
    glow = np.clip(1 - dist / 0.62, 0, 1) ** 2 * 46
    arr += glow[..., None]

    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB").convert("RGBA")


def rounded_outline(size: int, radius: int, width: int, color) -> Image.Image:
    layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    draw.rounded_rectangle(
        [size, size, SIZE - size, SIZE - size],
        radius=radius,
        outline=color,
        width=width,
    )
    return layer


def main() -> None:
    img = gradient()

    # 屏幕轮廓，暗示「全屏」
    img.alpha_composite(rounded_outline(112, 190, 12, (255, 255, 255, 46)))

    # 主字「清」+ 柔和投影
    font = ImageFont.truetype(FONT_BOLD, 486)
    text = "清"
    bbox = font.getbbox(text)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    pos = ((SIZE - tw) / 2 - bbox[0], 470 - th / 2 - bbox[1])

    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).text((pos[0], pos[1] + 14), text, font=font, fill=(6, 42, 90, 120))
    shadow = shadow.filter(ImageFilter.GaussianBlur(26))
    img.alpha_composite(shadow)

    draw = ImageDraw.Draw(img)
    draw.text(pos, text, font=font, fill=(255, 255, 255, 255))

    # 右下角「已拦截」徽标
    cx, cy, r = 792, 782, 118
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255, 255, 255, 255))
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(255, 255, 255, 90), width=10)

    draw.line(
        [(cx - 52, cy + 2), (cx - 12, cy + 44), (cx + 56, cy - 44)],
        fill=BADGE + (255,),
        width=26,
        joint="curve",
    )

    # 底部品牌字
    small = ImageFont.truetype(FONT_LIGHT, 46)
    label = "Q I N G P I N G"
    lb = small.getbbox(label)
    lw = lb[2] - lb[0]
    draw.text(((SIZE - lw) / 2 - lb[0], 892), label, font=small, fill=(255, 255, 255, 150))

    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.convert("RGB").save(OUT, "PNG")
    print("saved:", OUT, OUT.stat().st_size)

    preview = OUT.parent / "_preview-180.png"
    img.convert("RGB").resize((180, 180), Image.LANCZOS).save(preview, "PNG")
    print("preview:", preview)


if __name__ == "__main__":
    main()
