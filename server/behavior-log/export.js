'use strict';

// 把 behavior_events 导出为 CSV：会话汇总一份、逐条事件一份。
// 走 CloudBase CLI 的 `tcb db execute`，只需要本机装好 Node.js、
// 打过 `tcb login`，并且账号对这个环境有权限，不需要数据库密码。
//
// 用法：
//   node export.js                          # 导出全部数据到 ./export
//   node export.js --out D:/展览数据         # 指定输出目录
//   node export.js --from 2026-10-29 --to 2026-10-30   # 按服务器时间筛选
//   node export.js --env <环境ID>            # 默认读 cloudbaserc.json

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const PAGE_SIZE = 1000;
const TIME_PATTERN = /^\d{4}-\d{2}-\d{2}([T ]\d{2}:\d{2}(:\d{2})?)?$/;

function parseArgs(argv) {
  const args = { out: 'export', env: '', from: '', to: '' };
  for (let i = 0; i < argv.length; i += 1) {
    const key = argv[i];
    if (!key.startsWith('--')) {
      continue;
    }
    const name = key.slice(2);
    const value = argv[i + 1];
    if (!(name in args)) {
      throw new Error(`未知参数：${key}`);
    }
    if (value === undefined || value.startsWith('--')) {
      throw new Error(`参数 ${key} 缺少取值`);
    }
    args[name] = value;
    i += 1;
  }
  for (const name of ['from', 'to']) {
    if (args[name] && !TIME_PATTERN.test(args[name])) {
      throw new Error(`--${name} 需要 YYYY-MM-DD 或 YYYY-MM-DD HH:MM 格式`);
    }
  }
  return args;
}

function defaultEnv() {
  const configPath = path.join(__dirname, 'cloudbaserc.json');
  const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
  if (!config.envId) {
    throw new Error('cloudbaserc.json 里没有 envId，请用 --env 指定');
  }
  return config.envId;
}

function quote(value) {
  return `'${String(value).replace(/'/g, "''")}'`;
}

function timeFilter(column, args) {
  const clauses = [];
  if (args.from) {
    clauses.push(`${column} >= ${quote(args.from)}`);
  }
  if (args.to) {
    clauses.push(`${column} < ${quote(args.to)}`);
  }
  return clauses.length ? ` AND ${clauses.join(' AND ')}` : '';
}

// Windows 上 tcb 是 .cmd，需要经过 shell；这里自己给每个参数加双引号，
// 并把 SQL 压成单行，避免换行和 > < 被 shell 当成语法。
function shellArg(value) {
  return `"${String(value).replace(/"/g, '\\"')}"`;
}

function runQuery(env, sql) {
  let stdout;
  const args = [
    'tcb', 'db', 'execute', '-e', env, '--json', '--sql', sql.replace(/\s+/g, ' ').trim(),
  ];
  try {
    stdout = execSync(args.map(shellArg).join(' '), {
      encoding: 'utf8',
      maxBuffer: 64 * 1024 * 1024,
      windowsHide: true,
    });
  } catch (err) {
    const detail = (err.stderr || err.stdout || err.message || '').toString().trim();
    throw new Error(`tcb 执行失败：${detail}`);
  }
  const start = stdout.indexOf('{');
  const end = stdout.lastIndexOf('}');
  if (start < 0 || end < start) {
    throw new Error(`无法解析 tcb 输出：${stdout.slice(0, 200)}`);
  }
  const parsed = JSON.parse(stdout.slice(start, end + 1));
  const data = parsed.data || parsed;
  if (!Array.isArray(data.Rows)) {
    throw new Error(`查询结果里没有 Rows：${stdout.slice(0, 200)}`);
  }
  return {
    columns: data.Columns || [],
    rows: data.Rows.map((row) => JSON.parse(row)),
  };
}

function csvCell(value) {
  if (value === null || value === undefined) {
    return '';
  }
  const text = typeof value === 'object' ? JSON.stringify(value) : String(value);
  return `"${text.replace(/"/g, '""')}"`;
}

function writeCsv(filePath, columns, rows) {
  const lines = [columns.map(csvCell).join(',')];
  for (const row of rows) {
    lines.push(row.map(csvCell).join(','));
  }
  fs.writeFileSync(filePath, `﻿${lines.join('\r\n')}\r\n`, 'utf8');
}

function fetchAll(env, buildSql) {
  const columns = [];
  const rows = [];
  let offset = 0;
  for (;;) {
    const result = runQuery(env, buildSql(offset));
    if (result.columns.length) {
      columns.length = 0;
      columns.push(...result.columns);
    }
    rows.push(...result.rows);
    if (result.rows.length < PAGE_SIZE) {
      break;
    }
    offset += PAGE_SIZE;
  }
  return { columns, rows };
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const env = args.env || defaultEnv();
  const outDir = path.resolve(args.out);
  fs.mkdirSync(outDir, { recursive: true });

  const sessionsSql = (offset) => `
    SELECT session_id,
           to_char(min(server_time), 'YYYY-MM-DD HH24:MI:SS') AS started_at,
           to_char(max(server_time), 'YYYY-MM-DD HH24:MI:SS') AS last_seen,
           count(*) AS batches,
           sum(jsonb_array_length(events)) AS events,
           max(ua) AS user_agent
      FROM behavior_events
     WHERE true${timeFilter('server_time', args)}
     GROUP BY session_id
     ORDER BY started_at, session_id
     LIMIT ${PAGE_SIZE} OFFSET ${offset}`;

  const eventsSql = (offset) => `
    SELECT b.session_id AS session_id,
           to_char(b.server_time, 'YYYY-MM-DD HH24:MI:SS') AS server_time,
           (e->>'t')::bigint AS t_ms,
           e->>'n' AS event,
           e->'p' AS props
      FROM behavior_events b
      CROSS JOIN LATERAL jsonb_array_elements(b.events) e
     WHERE true${timeFilter('b.server_time', args)}
     ORDER BY b.id, (e->>'t')::bigint
     LIMIT ${PAGE_SIZE} OFFSET ${offset}`;

  console.log(`环境：${env}`);
  const sessions = fetchAll(env, sessionsSql);
  const sessionsPath = path.join(outDir, 'sessions.csv');
  writeCsv(sessionsPath, sessions.columns, sessions.rows);
  console.log(`会话汇总：${sessions.rows.length} 行 -> ${sessionsPath}`);

  const events = fetchAll(env, eventsSql);
  const eventsPath = path.join(outDir, 'events.csv');
  writeCsv(eventsPath, events.columns, events.rows);
  console.log(`逐条事件：${events.rows.length} 行 -> ${eventsPath}`);
}

try {
  main();
} catch (err) {
  console.error(`导出失败：${err.message}`);
  process.exitCode = 1;
}
