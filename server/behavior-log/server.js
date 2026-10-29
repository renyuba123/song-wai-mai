'use strict';

// HTTP 云函数的 Web Server 入口：把标准 HTTP 请求转给 index.main，
// 由后者负责校验、裁剪并写入 behavior_events。

const http = require('http');
const { main } = require('./index.js');

const PORT = Number(process.env.PORT) || 9000;
const MAX_BODY_BYTES = 64 * 1024;

const CORS = {
  'Content-Type': 'application/json; charset=utf-8',
};

const server = http.createServer((req, res) => {
  const chunks = [];
  let size = 0;
  let aborted = false;

  req.on('data', (chunk) => {
    size += chunk.length;
    if (size > MAX_BODY_BYTES) {
      aborted = true;
      res.writeHead(413, CORS);
      res.end(JSON.stringify({ error: 'payload_too_large' }));
      req.destroy();
      return;
    }
    chunks.push(chunk);
  });

  req.on('end', async () => {
    if (aborted) {
      return;
    }
    const event = {
      httpMethod: req.method,
      headers: req.headers,
      body: Buffer.concat(chunks).toString('utf8'),
      path: req.url,
    };
    try {
      const result = await main(event);
      res.writeHead(result.statusCode || 200, result.headers || CORS);
      res.end(result.body || '');
    } catch (err) {
      console.error(err);
      res.writeHead(500, CORS);
      res.end(JSON.stringify({ error: 'internal_error' }));
    }
  });
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`behavior-log listening on ${PORT}`);
});
