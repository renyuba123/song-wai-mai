"""根据 links.json 生成展览用的三个二维码。

用法：python generate_qr.py
链接确定后直接改 links.json 里的 url，再跑一次即可覆盖 output/ 下的图片。
"""

from __future__ import annotations

import json
from pathlib import Path

import qrcode
from qrcode.constants import ERROR_CORRECT_H

ROOT = Path(__file__).resolve().parent
LINKS = ROOT / "links.json"
OUTPUT = ROOT / "output"

# 固定顺序和文件名，保证重新生成时不会多出别的文件
SLOTS = [
    ("game", "qr-1-game.png", "1-打开游戏"),
    ("video", "qr-2-video.png", "2-演示视频"),
    ("analytics", "qr-3-analytics.png", "3-用户行为分析"),
]


def main() -> None:
    links = json.loads(LINKS.read_text(encoding="utf-8"))
    OUTPUT.mkdir(exist_ok=True)

    for key, filename, label in SLOTS:
        item = links[key]
        url = item["url"]
        if not url.startswith(("https://", "http://")):
            raise ValueError(f"{key} 的 url 必须以 http(s):// 开头：{url}")

        qr = qrcode.QRCode(
            version=None,
            error_correction=ERROR_CORRECT_H,
            box_size=16,
            border=4,
        )
        qr.add_data(url)
        qr.make(fit=True)
        image = qr.make_image(fill_color="black", back_color="white")
        target = OUTPUT / filename
        image.save(target)

        mark = "（占位）" if item.get("placeholder") else ""
        print(f"{label}{mark}: {url} -> {target.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
