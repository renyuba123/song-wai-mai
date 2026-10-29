#!/usr/bin/env python3
"""把导出的行为事件转成展览分析页可直接打开的数据，或生成示例数据。

用法：

    # 从导出的 behavior_events_events.csv 生成页面数据（不提交真实数据）
    python tools/build_behavior_page_data.py --csv exports/behavior-20261029/behavior_events_events.csv \
        --out exports/behavior-20261029/analytics.json

    # 重新生成随页面发布的示例数据（城市底图 + 一条演示轨迹）
    python tools/build_behavior_page_data.py --demo \
        --city exhibition/analytics/data/city-118.json \
        --out exhibition/analytics/data/sample-data.js --js

页面 JSON 结构：

    {
      "meta": {"label": ..., "city": 118, "demo": true, "generated_at": ...},
      "sessions": [{"id": "s...", "started_at": "...", "events": [{"n": ..., "t": ..., "p": {...}}]}]
    }

城市底图来自 tools/export_city_map.gd 导出的 city-118.json。
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
import math
from collections import defaultdict, deque
from pathlib import Path

SPEED_MIN = 2.0
SPEED_MAX = 12.0


def load_city(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def nearest_edge(city: dict, x: float, z: float) -> tuple[int, float]:
    """返回距离点最近的 (路段编号, 距离)。"""
    nodes = city["nodes"]
    best = (-1, math.inf)
    for edge_id, (a, b, _kind) in enumerate(city["edges"]):
        ax, az = nodes[a]
        bx, bz = nodes[b]
        dx, dz = bx - ax, bz - az
        length_sq = dx * dx + dz * dz
        if length_sq <= 0:
            continue
        t = max(0.0, min(1.0, ((x - ax) * dx + (z - az) * dz) / length_sq))
        px, pz = ax + dx * t, az + dz * t
        distance = math.hypot(x - px, z - pz)
        if distance < best[1]:
            best = (edge_id, distance)
    return best


def nearest_node(city: dict, x: float, z: float) -> int:
    nodes = city["nodes"]
    return min(range(len(nodes)), key=lambda index: math.hypot(nodes[index][0] - x, nodes[index][1] - z))


def shortest_route(city: dict, start_node: int, goal_node: int) -> list[int]:
    adjacency: dict[int, list[int]] = defaultdict(list)
    for a, b, _kind in city["edges"]:
        adjacency[a].append(b)
        adjacency[b].append(a)
    previous = {start_node: -1}
    queue = deque([start_node])
    while queue and goal_node not in previous:
        current = queue.popleft()
        for nxt in adjacency[current]:
            if nxt not in previous:
                previous[nxt] = current
                queue.append(nxt)
    if goal_node not in previous:
        return []
    route = []
    node = goal_node
    while node != -1:
        route.append(node)
        node = previous[node]
    route.reverse()
    return route


def polyline_between(city: dict, start_xy: tuple[float, float], end_xy: tuple[float, float]) -> list[tuple[float, float]]:
    start_node = nearest_node(city, *start_xy)
    end_node = nearest_node(city, *end_xy)
    route = shortest_route(city, start_node, end_node)
    nodes = city["nodes"]
    points = [start_xy]
    points.extend((nodes[index][0], nodes[index][1]) for index in route)
    points.append(end_xy)
    cleaned = [points[0]]
    for point in points[1:]:
        if math.hypot(point[0] - cleaned[-1][0], point[1] - cleaned[-1][1]) > 0.5:
            cleaned.append(point)
    return cleaned


def path_length(points: list[tuple[float, float]]) -> float:
    return sum(
        math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(points, points[1:])
    )


def point_at(points: list[tuple[float, float]], distance: float) -> tuple[float, float, float, int]:
    """沿折线走 distance 米，返回 (x, z, yaw_deg, 所在段序号)。"""
    remain = max(0.0, distance)
    for index, (a, b) in enumerate(zip(points, points[1:])):
        segment = math.hypot(b[0] - a[0], b[1] - a[1])
        if remain <= segment or index == len(points) - 2:
            ratio = 0.0 if segment <= 0 else min(1.0, remain / segment)
            x = a[0] + (b[0] - a[0]) * ratio
            z = a[1] + (b[1] - a[1]) * ratio
            yaw = math.degrees(math.atan2(-(b[0] - a[0]), -(b[1] - a[1])))
            return x, z, yaw, index
        remain -= segment
    x, z = points[-1]
    return x, z, 0.0, max(0, len(points) - 2)


def road_crowding(city: dict, x: float, z: float, seconds: float) -> dict:
    edge_id, _distance = nearest_edge(city, x, z)
    if edge_id < 0:
        return {"road": -1, "rk": -1, "cars": 0, "peds": 0, "near": 0}
    edge = city["edges"][edge_id]
    kind = edge[2]
    length = math.hypot(
        city["nodes"][edge[1]][0] - city["nodes"][edge[0]][0],
        city["nodes"][edge[1]][1] - city["nodes"][edge[0]][1],
    )
    bucket = int(seconds // 12)
    seed = edge_id * 7919 + bucket * 104729 + city["seed"]
    cars = 1 + (seed % (5 + kind * 2))
    peds = (seed // 7) % (3 + kind)
    near = max(0, min(cars, round(cars * 160.0 / max(length, 1.0))))
    return {"road": edge_id, "rk": kind, "cars": cars, "peds": peds, "near": near}


def build_demo_session(city: dict, index: int = 0) -> dict:
    starts = city.get("starts") or [[0.0, 0.0]]
    start_xy = tuple(starts[index % len(starts)])
    merchants = [site for site in city.get("sites", []) if site.get("k") == 0]
    customers = [site for site in city.get("sites", []) if site.get("k") == 1]
    merchant = merchants[index % len(merchants)] if merchants else {"x": 400.0, "z": 400.0}
    customer = customers[(index + 3) % len(customers)] if customers else {"x": -500.0, "z": 300.0}
    pickup_xy = (merchant["x"], merchant["z"])
    drop_xy = (customer["x"], customer["z"])

    to_pickup = polyline_between(city, start_xy, pickup_xy)
    to_drop = polyline_between(city, pickup_xy, drop_xy)
    pickup_distance = path_length(to_pickup)
    total_distance = pickup_distance + path_length(to_drop)
    step_time = 2.0
    speed_base = 7.2

    events: list[dict] = [
        {"n": "session", "t": 0, "p": {"w": 390, "h": 844, "touch": 1, "city": city["seed"]}},
        {
            "n": "offer",
            "t": 0,
            "p": {"seed": 9000 + index, "city": city["seed"], "pick": round(pickup_distance), "drop": round(total_distance - pickup_distance)},
        },
        {
            "n": "start",
            "t": 0,
            "p": {
                "seed": 9000 + index,
                "city": city["seed"],
                "sx": round(start_xy[0], 1),
                "sz": round(start_xy[1], 1),
                "px": round(pickup_xy[0], 1),
                "pz": round(pickup_xy[1], 1),
                "dx": round(drop_xy[0], 1),
                "dz": round(drop_xy[1], 1),
                "limit": round(total_distance / speed_base * 1.6 + 30),
            },
        },
    ]
    limit = events[2]["p"]["limit"]
    elapsed = 0.0
    travelled = 0.0
    checkpoints = 0
    picked = False
    while travelled < total_distance - 0.01 and elapsed < limit:
        elapsed += step_time
        speed = max(
            SPEED_MIN,
            min(SPEED_MAX, speed_base + 3.6 * math.sin(elapsed / 17.0 + index) + 1.2 * math.sin(elapsed / 4.3)),
        )
        travelled = min(total_distance, travelled + speed * step_time)
        if travelled <= pickup_distance:
            x, z, yaw, _segment = point_at(to_pickup, travelled)
            target = pickup_distance - travelled
        else:
            x, z, yaw, _segment = point_at(to_drop, travelled - pickup_distance)
            target = total_distance - travelled
            if not picked:
                picked = True
                remain = max(0.0, limit - elapsed)
                events.append({"n": "pickup", "t": round(elapsed * 1000), "p": {"sec": round(elapsed), "x": round(x, 1), "z": round(z, 1), "speed": round(speed, 1), "left": round(remain)}})
        props = {
            "x": round(x, 1),
            "z": round(z, 1),
            "yaw": round(yaw),
            "d": round(target),
            "left": round(max(0.0, limit - elapsed)),
            "speed": round(speed, 1),
        }
        props.update(road_crowding(city, x, z, elapsed))
        events.append({"n": "pos", "t": round(elapsed * 1000), "p": props})
        if elapsed >= (checkpoints + 1) * 30.0:
            checkpoints += 1
            checkpoint = {
                "i": checkpoints,
                "sec": round(elapsed),
                "x": round(x, 1),
                "z": round(z, 1),
                "speed": round(speed, 1),
                "left": round(max(0.0, limit - elapsed)),
            }
            checkpoint.update(road_crowding(city, x, z, elapsed))
            events.append({"n": "checkpoint", "t": round(elapsed * 1000), "p": checkpoint})
    events.append({
        "n": "finish",
        "t": round(elapsed * 1000),
        "p": {"ok": True, "why": "none", "sec": round(elapsed), "x": round(drop_xy[0], 1), "z": round(drop_xy[1], 1), "speed": round(speed, 1)},
    })
    return {
        "id": "demo-%d" % index,
        "started_at": None,
        "events": events,
        "summary": {"seed": 9000 + index, "result": "ok", "seconds": round(elapsed)},
    }


def build_demo(city: dict, count: int = 2) -> dict:
    return {
        "meta": {
            "label": "示例数据（演示轨迹，不是真实访客）",
            "city": city["seed"],
            "demo": True,
            "generated_at": dt.datetime.now().isoformat(timespec="seconds"),
        },
        "sessions": [build_demo_session(city, index) for index in range(count)],
    }


def build_from_csv(csv_path: Path) -> dict:
    sessions: dict[str, dict] = {}
    order: list[str] = []
    with csv_path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            session_id = (row.get("session_id") or "").strip()
            if not session_id or session_id.startswith("probe"):
                continue
            if session_id not in sessions:
                sessions[session_id] = {"id": session_id, "started_at": row.get("server_time"), "events": []}
                order.append(session_id)
            try:
                props = json.loads(row.get("props") or "{}")
            except json.JSONDecodeError:
                props = {}
            try:
                t = int(float(row.get("t_ms") or 0))
            except ValueError:
                t = 0
            sessions[session_id]["events"].append({"n": row.get("event_name") or "", "t": t, "p": props})
    city_seed = 118
    for session in sessions.values():
        for event in session["events"]:
            if event["n"] == "session" and isinstance(event["p"].get("city"), (int, float)):
                city_seed = int(event["p"]["city"])
                break
        for event in session["events"]:
            if event["n"] == "start" and isinstance(event["p"].get("city"), (int, float)):
                city_seed = int(event["p"]["city"])
                break
        for event in session["events"]:
            if event["n"] == "finish":
                session["summary"] = {"result": "ok" if event["p"].get("ok") else str(event["p"].get("why") or "fail"), "seconds": event["p"].get("sec")}
                break
    return {
        "meta": {
            "label": "导出数据 %s" % csv_path.name,
            "city": city_seed,
            "demo": False,
            "generated_at": dt.datetime.now().isoformat(timespec="seconds"),
        },
        "sessions": [sessions[session_id] for session_id in order],
    }


def write_output(data: dict, out_path: Path, city: dict | None, as_js: bool) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    if as_js:
        if city is None:
            raise SystemExit("--js 需要同时传入 --city")
        text = (
            "/* 由 tools/build_behavior_page_data.py 生成，请勿手工修改。 */\n"
            "window.SWM_CITY = %s;\n"
            "window.SWM_SAMPLE = %s;\n"
        ) % (
            json.dumps(city, ensure_ascii=False, separators=(",", ":")),
            json.dumps(data, ensure_ascii=False, separators=(",", ":")),
        )
    else:
        text = json.dumps(data, ensure_ascii=False, indent=2)
    out_path.write_text(text + "\n", encoding="utf-8")
    print("写入 %s（%d 个会话）" % (out_path, len(data["sessions"])))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--csv", type=Path, help="导出的 behavior_events_events.csv")
    parser.add_argument("--demo", action="store_true", help="生成示例轨迹，而不是读取导出数据")
    parser.add_argument("--city", type=Path, default=Path("exhibition/analytics/data/city-118.json"), help="城市底图 JSON")
    parser.add_argument("--out", type=Path, required=True, help="输出文件")
    parser.add_argument("--js", action="store_true", help="输出供页面直接加载的 .js（包含城市底图）")
    parser.add_argument("--sessions", type=int, default=2, help="示例会话数量")
    args = parser.parse_args()

    city = load_city(args.city) if args.city.exists() else None
    if args.demo:
        if city is None:
            raise SystemExit("缺少城市底图：%s" % args.city)
        data = build_demo(city, max(1, args.sessions))
    elif args.csv:
        data = build_from_csv(args.csv)
    else:
        raise SystemExit("需要 --csv 或 --demo")
    write_output(data, args.out, city, args.js)


if __name__ == "__main__":
    main()
