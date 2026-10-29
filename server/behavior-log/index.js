'use strict';

// 展览行为采集 HTTP 云函数：接收游戏端批量事件，落库到 behavior_events。
// 客户端只带随机会话 ID，不采集姓名、账号或设备标识；服务端也不存 IP。

const cloud = require('@cloudbase/node-sdk');

const app = cloud.init({ env: cloud.SYMBOL_CURRENT_ENV });

// 环境是 PostgreSQL 版：用 rdb() 走平台内部链路写入，不需要也不支持文档型数据库。
const TABLE = 'behavior_events';
const MAX_BODY_BYTES = 64 * 1024;
const MAX_EVENTS = 50;
const MAX_EVENT_NAME = 40;
const MAX_PROPS_KEYS = 16;
const MAX_STRING = 120;

// CORS 响应头由 CloudBase 网关按请求 Origin 自动补齐；函数再写
// Access-Control-Allow-Origin 会与网关的值拼接成非法头，浏览器直接拒绝。
const RESPONSE_HEADERS = {
  'Content-Type': 'application/json; charset=utf-8',
};

function reply(statusCode, payload) {
  return {
    statusCode,
    headers: RESPONSE_HEADERS,
    body: JSON.stringify(payload || {}),
    isBase64Encoded: false,
  };
}

function sanitizeValue(value) {
  if (typeof value === 'number') {
    return Number.isFinite(value) ? value : null;
  }
  if (typeof value === 'boolean') {
    return value;
  }
  if (typeof value === 'string') {
    return value.slice(0, MAX_STRING);
  }
  return null;
}

function sanitizeProps(props) {
  if (!props || typeof props !== 'object' || Array.isArray(props)) {
    return {};
  }
  const clean = {};
  for (const key of Object.keys(props)) {
    if (Object.keys(clean).length >= MAX_PROPS_KEYS) {
      break;
    }
    if (typeof key !== 'string' || key.length === 0 || key.length > 32) {
      continue;
    }
    const value = sanitizeValue(props[key]);
    if (value !== null) {
      clean[key] = value;
    }
  }
  return clean;
}

function sanitizeEvents(events) {
  const clean = [];
  for (const event of events) {
    if (clean.length >= MAX_EVENTS) {
      break;
    }
    if (!event || typeof event !== 'object') {
      continue;
    }
    const name = typeof event.n === 'string' ? event.n.slice(0, MAX_EVENT_NAME) : '';
    if (!name) {
      continue;
    }
    const t = Number.isFinite(event.t) ? Math.max(0, Math.round(event.t)) : 0;
    clean.push({ n: name, t, p: sanitizeProps(event.p) });
  }
  return clean;
}

exports.main = async (event) => {
  const method = (event && event.httpMethod) || 'POST';
  if (method === 'OPTIONS') {
    return reply(204, {});
  }
  if (method !== 'POST') {
    return reply(405, { error: 'method_not_allowed' });
  }

  let raw = (event && event.body) || '';
  if (event && event.isBase64Encoded) {
    raw = Buffer.from(raw, 'base64').toString('utf8');
  }
  if (Buffer.byteLength(raw, 'utf8') > MAX_BODY_BYTES) {
    return reply(413, { error: 'payload_too_large' });
  }

  let payload;
  try {
    payload = JSON.parse(raw);
  } catch (err) {
    return reply(400, { error: 'invalid_json' });
  }

  const expectedToken = process.env.LOG_TOKEN || '';
  if (expectedToken && payload.token !== expectedToken) {
    return reply(403, { error: 'forbidden' });
  }

  const sessionId = typeof payload.session_id === 'string' ? payload.session_id : '';
  if (!/^[A-Za-z0-9_-]{8,64}$/.test(sessionId)) {
    return reply(400, { error: 'invalid_session' });
  }

  const events = Array.isArray(payload.events) ? sanitizeEvents(payload.events) : [];
  if (events.length === 0) {
    return reply(204, {});
  }

  const headers = (event && event.headers) || {};
  const userAgent = String(headers['user-agent'] || headers['User-Agent'] || '').slice(0, 200);

  const { error } = await app.rdb().from(TABLE).insert({
    session_id: sessionId,
    client_start: Number.isFinite(payload.start) ? Math.round(payload.start) : 0,
    ua: userAgent,
    events,
  });
  if (error) {
    console.error('behavior_events insert failed', error);
    return reply(500, { error: 'storage_unavailable' });
  }

  return reply(204, {});
};
