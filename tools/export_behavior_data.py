#!/usr/bin/env python3
"""导出 CloudBase PostgreSQL 的 behavior_events 表。

只执行 SELECT，不修改云端数据。查询通过 CloudBase CLI 的
`tcb db execute --json` 完成，需要先在本机登录有权限的腾讯云账号：

    tcb login
    tcb env list

用法：

    python tools/export_behavior_data.py
    python tools/export_behavior_data.py --out exports/behavior-20261029
    python tools/export_behavior_data.py --since 2026-10-29 --until 2026-10-30

输出目录里会有：

    behavior_events.csv        一条数据库记录一行，events 保留原始 JSON
    behavior_events_events.csv 一条事件一行，方便在 Excel 里透视
    summary.json               行数、会话数、事件计数和导出参数
"""

import argparse
import csv
import json
import os
import shutil
import subprocess
import sys
from collections import Counter
from datetime import datetime

DEFAULT_ENV = "passive-sailfish-d0e1nvt8175333a"
TABLE = "public.behavior_events"
RAW_FIELDS = [
    "id",
    "session_id",
    "client_start",
    "server_time",
    "ua",
    "created_at",
    "events",
]
FLAT_FIELDS = [
    "row_id",
    "session_id",
    "server_time",
    "event_name",
    "t_ms",
    "props",
]


def find_tcb():
    path = shutil.which("tcb")
    if not path:
        sys.exit(
            "找不到 tcb 命令。先安装 CloudBase CLI：\n"
            "  npm install -g @cloudbase/cli\n"
            "再登录：tcb login"
        )
    return path


def run_sql(tcb, env, sql):
    command = [tcb, "db", "execute", "-e", env, "--sql", sql, "--json"]
    proc = subprocess.run(
        command,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if proc.returncode != 0:
        sys.exit(
            "tcb 执行失败（退出码 %s）：\n%s\n%s"
            % (proc.returncode, proc.stdout.strip(), proc.stderr.strip())
        )

    text = proc.stdout.strip()
    start = text.find("{")
    if start < 0:
        sys.exit("tcb 没有返回 JSON，原始输出：\n%s" % text)
    try:
        payload = json.loads(text[start:])
    except json.JSONDecodeError as exc:
        sys.exit("解析 tcb 输出失败：%s\n原始输出：\n%s" % (exc, text))

    data = payload.get("data") or {}
    if data.get("Error"):
        sys.exit("数据库返回错误：%s" % json.dumps(data["Error"], ensure_ascii=False))

    columns = data.get("Columns") or []
    rows = []
    for raw in data.get("Rows") or []:
        values = json.loads(raw) if isinstance(raw, str) else raw
        rows.append(dict(zip(columns, values)))
    return rows


def quote(value):
    return "'" + str(value).replace("'", "''") + "'"


def build_where(since, until):
    clauses = []
    if since:
        clauses.append("server_time >= %s" % quote(since))
    if until:
        clauses.append("server_time < %s" % quote(until))
    return (" AND " + " AND ".join(clauses)) if clauses else ""


def export_rows(tcb, env, since, until, batch_size):
    where = build_where(since, until)
    count_rows = run_sql(
        tcb,
        env,
        "SELECT count(*) AS n FROM %s WHERE true%s" % (TABLE, where),
    )
    total = int(count_rows[0]["n"]) if count_rows else 0
    print("待导出 %d 行" % total, file=sys.stderr)

    rows = []
    last_id = 0
    while True:
        sql = (
            "SELECT id, session_id, client_start, server_time, ua, "
            "events::text AS events, created_at "
            "FROM %s WHERE id > %d%s ORDER BY id LIMIT %d"
            % (TABLE, last_id, where, batch_size)
        )
        batch = run_sql(tcb, env, sql)
        if not batch:
            break
        rows.extend(batch)
        last_id = int(batch[-1]["id"])
        print("已读取 %d / %d 行" % (len(rows), total), file=sys.stderr)
        if len(batch) < batch_size:
            break
    return rows


def write_outputs(rows, out_dir, meta):
    os.makedirs(out_dir, exist_ok=True)
    raw_path = os.path.join(out_dir, "behavior_events.csv")
    flat_path = os.path.join(out_dir, "behavior_events_events.csv")

    sessions = set()
    event_counts = Counter()

    with open(raw_path, "w", newline="", encoding="utf-8-sig") as raw_file, open(
        flat_path, "w", newline="", encoding="utf-8-sig"
    ) as flat_file:
        raw_writer = csv.DictWriter(raw_file, fieldnames=RAW_FIELDS)
        raw_writer.writeheader()
        flat_writer = csv.DictWriter(flat_file, fieldnames=FLAT_FIELDS)
        flat_writer.writeheader()

        for row in rows:
            sessions.add(row["session_id"])
            raw_writer.writerow({field: row.get(field, "") for field in RAW_FIELDS})
            try:
                events = json.loads(row.get("events") or "[]")
            except json.JSONDecodeError:
                events = []
            for event in events:
                name = event.get("n", "")
                event_counts[name] += 1
                flat_writer.writerow(
                    {
                        "row_id": row["id"],
                        "session_id": row["session_id"],
                        "server_time": row["server_time"],
                        "event_name": name,
                        "t_ms": event.get("t", ""),
                        "props": json.dumps(event.get("p", {}), ensure_ascii=False),
                    }
                )

    summary = {
        "exported_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "environment": meta["env"],
        "table": TABLE,
        "since": meta["since"],
        "until": meta["until"],
        "rows": len(rows),
        "sessions": len(sessions),
        "events": dict(sorted(event_counts.items())),
        "files": [raw_path, flat_path],
    }
    summary_path = os.path.join(out_dir, "summary.json")
    with open(summary_path, "w", encoding="utf-8") as summary_file:
        json.dump(summary, summary_file, ensure_ascii=False, indent=2)

    return raw_path, flat_path, summary_path, summary


def main():
    parser = argparse.ArgumentParser(description="导出 behavior_events 表为 CSV")
    parser.add_argument("--env", default=os.environ.get("TCB_ENV_ID", DEFAULT_ENV))
    parser.add_argument(
        "--out",
        default=os.path.join("exports", "behavior-" + datetime.now().strftime("%Y%m%d-%H%M%S")),
        help="输出目录，默认 exports/behavior-<时间>",
    )
    parser.add_argument("--since", help="server_time 下限，含，例如 2026-10-29 或 2026-10-29T00:00:00+08:00")
    parser.add_argument("--until", help="server_time 上限，不含，格式同上")
    parser.add_argument("--batch-size", type=int, default=500)
    args = parser.parse_args()

    tcb = find_tcb()
    rows = export_rows(tcb, args.env, args.since, args.until, args.batch_size)
    raw_path, flat_path, summary_path, summary = write_outputs(
        rows,
        args.out,
        {"env": args.env, "since": args.since, "until": args.until},
    )

    print("导出行数：%d" % summary["rows"])
    print("会话数：%d" % summary["sessions"])
    print("事件计数：%s" % json.dumps(summary["events"], ensure_ascii=False))
    print("原始记录：%s" % raw_path)
    print("事件明细：%s" % flat_path)
    print("汇总：%s" % summary_path)


if __name__ == "__main__":
    main()
