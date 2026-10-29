#!/usr/bin/env python3
"""把从服务器导出的行为数据渲染成地图 PNG。

用法：

    # 直接用导出脚本得到的 behavior_events_events.csv
    python tools/render_behavior_png.py \
        --csv exports/behavior-20261029/behavior_events_events.csv

    # 已经转好的页面 JSON
    python tools/render_behavior_png.py \
        --json exports/behavior-20261029/analytics.json \
        --out exports/behavior-20261029/map.png

    # 每个会话各出一张
    python tools/render_behavior_png.py \
        --json exports/behavior-20261029/analytics.json --all

脚本不连数据库，也不自己画图：它把数据嵌进一份临时的分析页，
再用 Edge / Chrome 的无头模式截图，所以得到的图和页面上
「下载地图 PNG」完全一致（路网、拥挤度、速度热力轨迹、任务点、计时点）。
需要本机装有 Microsoft Edge 或 Google Chrome。

没有 `pos` 事件的旧数据也能运行，但图上只有路网和任务点，不会有轨迹；
先确认线上游戏已经是记录位置、速度和道路信息的新版本。
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))

from build_behavior_page_data import build_from_csv  # noqa: E402

PAGE_DIR = ROOT / "exhibition" / "analytics"
DEFAULT_CITY = PAGE_DIR / "data" / "city-118.json"

BROWSER_CANDIDATES = [
    os.environ.get("SWM_BROWSER"),
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    shutil.which("msedge"),
    shutil.which("microsoft-edge"),
    shutil.which("google-chrome"),
    shutil.which("chromium"),
    "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
]

RENDER_STYLE = """
<style>
  html, body {
    height: 100% !important;
    min-height: 100% !important;
    margin: 0 !important;
    padding: 0 !important;
    overflow: hidden !important;
    background: #0a121a !important;
  }
  body > * { display: none !important; }
  body > main { display: block !important; }
  main { max-width: none !important; margin: 0 !important; }
  main > header, .toolbar, aside.panel, .note { display: none !important; }
  .stage { display: block !important; gap: 0 !important; }
  .canvasWrap {
    width: 100vw !important;
    height: 100vh !important;
    max-height: none !important;
    aspect-ratio: auto !important;
    margin: 0 !important;
    border: 0 !important;
    border-radius: 0 !important;
    box-shadow: none !important;
  }
  .tooltip { display: none !important; }
</style>
"""


def load_input(args: argparse.Namespace) -> tuple[dict, dict, Path]:
    for name in ("index.html", "analytics.css", "analytics.js"):
        if not (PAGE_DIR / name).is_file():
            raise SystemExit("分析页文件缺失：%s" % (PAGE_DIR / name))
    city_path = Path(args.city)
    if not city_path.is_file():
        raise SystemExit("找不到城市底图：%s" % city_path)
    city = json.loads(city_path.read_text(encoding="utf-8"))

    if args.csv:
        source = Path(args.csv)
        if not source.is_file():
            raise SystemExit("找不到 CSV：%s" % source)
        data = build_from_csv(source)
    elif args.json:
        source = Path(args.json)
        if not source.is_file():
            raise SystemExit("找不到 JSON：%s" % source)
        data = json.loads(source.read_text(encoding="utf-8"))
    else:
        raise SystemExit("请用 --csv 或 --json 指定数据来源")

    sessions = data.get("sessions")
    if not isinstance(sessions, list) or not sessions:
        raise SystemExit("数据里没有可渲染的会话")

    if args.session:
        wanted = args.session
        matches = [
            session for session in sessions
            if wanted == session.get("id") or wanted in str(session.get("id", ""))
        ]
        if not matches:
            raise SystemExit("找不到会话 %s；现有会话：%s" % (
                wanted, ", ".join(str(s.get("id", "?")) for s in sessions[:10])
            ))
        data = dict(data)
        data["sessions"] = [matches[0]]
    return city, data, source


def default_outputs(source: Path, args: argparse.Namespace) -> tuple[Path, Path | None]:
    """返回 (PNG 输出路径或目录, CSV 转换出的页面 JSON 路径)。"""
    page_json = None
    if args.csv:
        page_json = Path(args.json_out) if args.json_out else source.parent / "analytics.json"
    if args.out:
        out = Path(args.out)
    elif args.csv:
        out = source.parent / ("maps" if args.all else "analytics-map.png")
    else:
        out = source.parent / (source.stem + ("-maps" if args.all else "-map.png"))
    return out, page_json


def find_browser(explicit: str | None) -> Path:
    candidates = [explicit] if explicit else BROWSER_CANDIDATES
    for candidate in candidates:
        if not candidate:
            continue
        path = Path(candidate)
        if path.is_file():
            return path
    raise SystemExit(
        "找不到 Edge / Chrome。请安装其一，或用 --browser 指定浏览器可执行文件；"
        "也可以设置环境变量 SWM_BROWSER。"
    )


def safe_name(value: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9_.-]+", "_", value).strip("._")
    return cleaned[:40] or "session"


def make_workdir(city: dict, data: dict) -> Path:
    work = Path(tempfile.mkdtemp(prefix="swm-behavior-render-"))
    shutil.copy2(PAGE_DIR / "analytics.css", work / "analytics.css")
    shutil.copy2(PAGE_DIR / "analytics.js", work / "analytics.js")
    (work / "data").mkdir()
    script = (
        "/* 由 tools/render_behavior_png.py 临时生成。 */\n"
        "window.SWM_CITY = %s;\n"
        "window.SWM_SAMPLE = %s;\n"
    ) % (
        json.dumps(city, ensure_ascii=False, separators=(",", ":")),
        json.dumps(data, ensure_ascii=False, separators=(",", ":")),
    )
    (work / "data" / "sample-data.js").write_text(script + "\n", encoding="utf-8")
    html = (PAGE_DIR / "index.html").read_text(encoding="utf-8")
    html = html.replace("</head>", RENDER_STYLE + "\n</head>", 1)
    (work / "render.html").write_text(html, encoding="utf-8")
    return work


def screenshot(browser: Path, work: Path, out: Path, size: int) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    profile = Path(tempfile.mkdtemp(prefix="swm-browser-profile-"))
    url = (work / "render.html").as_uri()
    common = [
        str(browser),
        "--disable-gpu",
        "--hide-scrollbars",
        "--allow-file-access-from-files",
        "--force-device-scale-factor=1",
        "--no-first-run",
        "--no-default-browser-check",
        "--disable-extensions",
        "--user-data-dir=%s" % profile,
        "--window-size=%d,%d" % (size, size),
        "--virtual-time-budget=8000",
        "--screenshot=%s" % out.resolve(),
    ]
    errors: list[str] = []
    try:
        for headless in ("--headless=new", "--headless"):
            if out.exists():
                out.unlink()
            command = [common[0], headless] + common[1:] + [url]
            try:
                result = subprocess.run(
                    command,
                    capture_output=True,
                    text=True,
                    encoding="utf-8",
                    errors="replace",
                    timeout=120,
                )
            except subprocess.TimeoutExpired:
                errors.append("%s: 超过 120 秒" % headless)
                continue
            if out.is_file() and out.stat().st_size > 1000:
                return
            detail = (result.stderr or result.stdout or "").strip().splitlines()
            errors.append("%s: 退出码 %d %s" % (
                headless, result.returncode, detail[-1] if detail else ""
            ))
    finally:
        shutil.rmtree(profile, ignore_errors=True)
    raise SystemExit("浏览器没有生成截图：\n  " + "\n  ".join(errors))


def render_one(
    browser: Path,
    city: dict,
    data: dict,
    out: Path,
    size: int,
    keep_workdir: bool,
) -> None:
    work = make_workdir(city, data)
    try:
        screenshot(browser, work, out, size)
    finally:
        if keep_workdir:
            print("临时页面保留在 %s" % work)
        else:
            shutil.rmtree(work, ignore_errors=True)
    size_kb = out.stat().st_size / 1024
    print("写入 %s（%.0f KB，%d×%d）" % (out, size_kb, size, size))


def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--csv", type=Path, help="导出的 behavior_events_events.csv")
    source.add_argument("--json", type=Path, help="已经转好的页面 JSON（analytics.json）")
    parser.add_argument("--city", type=Path, default=DEFAULT_CITY, help="城市底图 JSON")
    parser.add_argument("--session", help="只渲染指定会话；可写完整或部分会话 ID")
    parser.add_argument("--all", action="store_true", help="每个会话各渲染一张")
    parser.add_argument("--out", type=Path, help="输出 PNG；--all 时作为输出目录")
    parser.add_argument("--json-out", type=Path, help="--csv 时同时写出的页面 JSON")
    parser.add_argument("--size", type=int, default=2000, help="截图边长，默认 2000")
    parser.add_argument("--browser", help="Edge / Chrome 可执行文件路径")
    parser.add_argument("--keep", action="store_true", help="保留临时页面，方便排查")
    args = parser.parse_args()

    if args.size < 600:
        raise SystemExit("--size 至少 600")
    if args.all and args.out and args.out.suffix.lower() == ".png":
        raise SystemExit("--all 时 --out 应该是目录，不是单个 PNG")

    if args.json_out and not args.csv:
        raise SystemExit("--json-out 只用于 --csv，请改用 --out 指定 PNG")

    city, data, source = load_input(args)
    out, page_json = default_outputs(source, args)
    if not args.all and out.is_dir():
        out = out / "behavior-map.png"
    if args.all and out.exists() and not out.is_dir():
        raise SystemExit("--all 的输出位置不是目录：%s" % out)
    if page_json is not None:
        page_json.parent.mkdir(parents=True, exist_ok=True)
        page_json.write_text(
            json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        print("写入 %s（%d 个会话）" % (page_json, len(data["sessions"])))

    browser = find_browser(args.browser)
    sessions = data["sessions"]
    if not args.all and len(sessions) > 1:
        print("共有 %d 个会话，默认渲染第 1 个；用 --all 或 --session 选择。" % len(sessions))

    if args.all:
        out.mkdir(parents=True, exist_ok=True)
        for index, session in enumerate(sessions, start=1):
            session_data = {"meta": data.get("meta", {}), "sessions": [session]}
            path = out / ("behavior-map-%02d-%s.png" % (
                index, safe_name(str(session.get("id", "session")))
            ))
            report(session)
            render_one(browser, city, session_data, path, args.size, args.keep)
    else:
        session = sessions[0]
        report(session)
        render_one(browser, city, data, out, args.size, args.keep)


def report(session: dict) -> None:
    events = session.get("events") or []
    counts: dict[str, int] = {}
    for event in events:
        name = str(event.get("n", ""))
        counts[name] = counts.get(name, 0) + 1
    print(
        "会话 %s：%d 条事件，位置 %d，计时点 %d，取餐 %d，结算 %d" % (
            session.get("id", "?"),
            len(events),
            counts.get("pos", 0),
            counts.get("checkpoint", 0),
            counts.get("pickup", 0),
            counts.get("finish", 0),
        )
    )
    if counts.get("pos", 0) == 0:
        print("提示：这个会话没有 pos 事件，图上不会有轨迹；"
              "旧版 Web 构建或未开始配送的会话都是这样。")


if __name__ == "__main__":
    main()
