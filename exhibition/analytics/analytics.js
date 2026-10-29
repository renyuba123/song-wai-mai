(() => {
  'use strict';

  const CITY = window.SWM_CITY || null;
  const SPEED_STOPS = [
    [0.0, [63, 167, 255]],
    [0.45, [79, 224, 192]],
    [0.7, [255, 209, 102]],
    [1.0, [255, 77, 109]],
  ];
  const CROWD_STOPS = [
    [0.0, [36, 64, 90]],
    [0.4, [46, 158, 122]],
    [0.72, [255, 176, 46]],
    [1.0, [255, 90, 60]],
  ];
  const KIND_NAMES = ['主干路', '次干路', '支路'];

  const el = {
    canvas: document.getElementById('map'),
    wrap: document.getElementById('canvasWrap'),
    tooltip: document.getElementById('tooltip'),
    sessionSelect: document.getElementById('sessionSelect'),
    metaLine: document.getElementById('metaLine'),
    demoBadge: document.getElementById('demoBadge'),
    stats: document.getElementById('stats'),
    roadInfo: document.getElementById('roadInfo'),
    dataNote: document.getElementById('dataNote'),
    toggleCrowd: document.getElementById('toggleCrowd'),
    toggleCheckpoints: document.getElementById('toggleCheckpoints'),
    fileInput: document.getElementById('fileInput'),
    downloadJson: document.getElementById('downloadJson'),
    downloadCsv: document.getElementById('downloadCsv'),
    downloadPng: document.getElementById('downloadPng'),
  };
  const ctx = el.canvas.getContext('2d');

  const state = {
    city: CITY,
    data: null,
    session: null,
    analysis: null,
    showCrowd: true,
    showCheckpoints: true,
    hover: null,
    view: null,
    width: 0,
    height: 0,
  };

  // ---------- 小工具 ----------

  function clamp(value, min, max) {
    return Math.max(min, Math.min(max, value));
  }

  function lerpColor(stops, t) {
    const value = clamp(t, 0, 1);
    for (let i = 1; i < stops.length; i += 1) {
      const [stop, color] = stops[i];
      const [prevStop, prevColor] = stops[i - 1];
      if (value <= stop) {
        const ratio = stop === prevStop ? 0 : (value - prevStop) / (stop - prevStop);
        const mixed = prevColor.map((channel, index) => Math.round(channel + (color[index] - channel) * ratio));
        return `rgb(${mixed[0]},${mixed[1]},${mixed[2]})`;
      }
    }
    return `rgb(${stops[stops.length - 1][1].join(',')})`;
  }

  function distance2(a, b) {
    return Math.hypot(a.x - b.x, a.y - b.y);
  }

  function formatTime(seconds) {
    const safe = Number.isFinite(Number(seconds)) ? Number(seconds) : 0;
    const value = Math.max(0, Math.round(safe));
    return `${String(Math.floor(value / 60)).padStart(2, '0')}:${String(value % 60).padStart(2, '0')}`;
  }

  function formatDuration(seconds) {
    const value = Math.max(0, Math.round(seconds));
    if (value < 60) return `${value} 秒`;
    return `${Math.floor(value / 60)} 分 ${String(value % 60).padStart(2, '0')} 秒`;
  }

  function resultText(finish) {
    if (!finish) return '未完成';
    if (finish.p && finish.p.ok) return '成功送达';
    const reason = finish.p && finish.p.why;
    if (reason === 'timeout') return '超时失败';
    if (reason === 'hit') return '被车撞倒';
    return '失败';
  }

  function pointOf(event) {
    if (!event || !event.p) return null;
    const x = Number(event.p.x);
    const z = Number(event.p.z);
    if (!Number.isFinite(x) || !Number.isFinite(z)) return null;
    return { x, z };
  }

  function edgeLength(city, edge) {
    const a = city.nodes[edge[0]];
    const b = city.nodes[edge[1]];
    return Math.hypot(b[0] - a[0], b[1] - a[1]);
  }

  // ---------- 数据整理 ----------

  function analyze(session) {
    const city = state.city;
    const events = (session.events || []).slice().sort((a, b) => (a.t || 0) - (b.t || 0));
    const find = (name) => events.find((event) => event.n === name) || null;
    const startEvent = find('start');
    const finishEvent = find('finish');
    const pickupEvent = find('pickup');
    const offerEvent = find('offer');

    const points = [];
    let last = null;
    for (const event of events) {
      if (event.n !== 'pos' || !event.p) continue;
      const x = Number(event.p.x);
      const z = Number(event.p.z);
      if (!Number.isFinite(x) || !Number.isFinite(z)) continue;
      let speed = Number(event.p.speed);
      if (!Number.isFinite(speed) || speed < 0) {
        if (last && event.t > last.t) {
          speed = Math.hypot(x - last.x, z - last.z) / ((event.t - last.t) / 1000);
        } else {
          speed = 0;
        }
      }
      points.push({
        t: event.t,
        x,
        z,
        speed,
        yaw: Number(event.p.yaw) || 0,
        road: Number.isFinite(Number(event.p.road)) ? Number(event.p.road) : -1,
        rk: Number.isFinite(Number(event.p.rk)) ? Number(event.p.rk) : -1,
        cars: Number(event.p.cars) || 0,
        peds: Number(event.p.peds) || 0,
        near: Number(event.p.near) || 0,
        left: Number(event.p.left) || 0,
        d: Number(event.p.d) || 0,
        source: 'pos',
      });
      last = points[points.length - 1];
    }

    const startPoint = startEvent && startEvent.p && Number.isFinite(Number(startEvent.p.sx))
      ? { x: Number(startEvent.p.sx), z: Number(startEvent.p.sz) }
      : points[0] || null;
    const pickupPoint = startEvent && startEvent.p && Number.isFinite(Number(startEvent.p.px))
      ? { x: Number(startEvent.p.px), z: Number(startEvent.p.pz) }
      : pointOf(pickupEvent);
    const dropPoint = startEvent && startEvent.p && Number.isFinite(Number(startEvent.p.dx))
      ? { x: Number(startEvent.p.dx), z: Number(startEvent.p.dz) }
      : pointOf(finishEvent) || (points.length ? points[points.length - 1] : null);

    let duration = finishEvent && finishEvent.p && Number.isFinite(Number(finishEvent.p.sec))
      ? Number(finishEvent.p.sec)
      : (points.length ? (points[points.length - 1].t - points[0].t) / 1000 : 0);
    let pathLength = 0;
    for (let i = 1; i < points.length; i += 1) {
      pathLength += Math.hypot(points[i].x - points[i - 1].x, points[i].z - points[i - 1].z);
    }
    const speeds = points.map((point) => point.speed).filter((speed) => Number.isFinite(speed) && speed >= 0);
    const maxSpeed = speeds.length ? Math.max(...speeds) : 0;
    const avgSpeed = duration > 0 ? pathLength / duration : 0;
    const speedFloor = Math.max(0, Math.min(...(speeds.length ? speeds : [0])));
    const speedCeiling = Math.max(speedFloor + 0.1, maxSpeed);

    let checkpoints = events
      .filter((event) => event.n === 'checkpoint' && event.p)
      .map((event) => ({
        t: event.t,
        sec: Number(event.p.sec) || 0,
        x: Number(event.p.x),
        z: Number(event.p.z),
        speed: Number(event.p.speed) || 0,
        road: Number.isFinite(Number(event.p.road)) ? Number(event.p.road) : -1,
        rk: Number.isFinite(Number(event.p.rk)) ? Number(event.p.rk) : -1,
        cars: Number(event.p.cars) || 0,
        peds: Number(event.p.peds) || 0,
        near: Number(event.p.near) || 0,
        left: Number(event.p.left) || 0,
      }))
      .filter((checkpoint) => Number.isFinite(checkpoint.x) && Number.isFinite(checkpoint.z));

    if (checkpoints.length === 0) {
      let nextAt = 30;
      for (const point of points) {
        const elapsed = (point.t - (points[0] ? points[0].t : 0)) / 1000;
        if (elapsed >= nextAt) {
          checkpoints.push({
            t: point.t,
            sec: elapsed,
            x: point.x,
            z: point.z,
            speed: point.speed,
            road: point.road,
            rk: point.rk,
            cars: point.cars,
            peds: point.peds,
            near: point.near,
            left: point.left,
            derived: true,
          });
          nextAt += 30;
        }
      }
    }

    const edgeStats = new Map();
    let maxDensity = 0;
    for (const point of points) {
      if (!city || !(point.road >= 0) || !city.edges[point.road]) continue;
      const length = Math.max(1, edgeLength(city, city.edges[point.road]));
      const density = (point.cars / length) * 100;
      const entry = edgeStats.get(point.road) || {
        edge: point.road,
        maxDensity: 0,
        sumDensity: 0,
        samples: 0,
        maxCars: 0,
        maxPeds: 0,
        maxNear: 0,
        kind: point.rk,
      };
      entry.maxDensity = Math.max(entry.maxDensity, density);
      entry.sumDensity += density;
      entry.samples += 1;
      entry.maxCars = Math.max(entry.maxCars, point.cars);
      entry.maxPeds = Math.max(entry.maxPeds, point.peds);
      entry.maxNear = Math.max(entry.maxNear, point.near);
      entry.kind = point.rk;
      edgeStats.set(point.road, entry);
      maxDensity = Math.max(maxDensity, density);
    }

    return {
      startEvent,
      offerEvent,
      pickupEvent,
      finishEvent,
      points,
      checkpoints,
      startPoint,
      pickupPoint,
      dropPoint,
      duration,
      pathLength,
      maxSpeed,
      avgSpeed,
      speedFloor,
      speedCeiling,
      edgeStats,
      maxDensity,
    };
  }

  // ---------- 画布 ----------

  function resize() {
    const rect = el.wrap.getBoundingClientRect();
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    state.width = rect.width;
    state.height = rect.height;
    el.canvas.width = Math.round(rect.width * dpr);
    el.canvas.height = Math.round(rect.height * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    draw();
  }

  function makeView() {
    const city = state.city;
    const mapWidth = city && city.map ? city.map[0] : 2400;
    const mapHeight = city && city.map ? city.map[1] : 2400;
    const pad = Math.max(16, Math.min(state.width, state.height) * 0.05);
    const scale = Math.min((state.width - pad * 2) / mapWidth, (state.height - pad * 2) / mapHeight);
    return {
      scale,
      centerX: state.width / 2,
      centerY: state.height / 2,
      mapWidth,
      mapHeight,
    };
  }

  function toScreen(point, view) {
    return {
      x: view.centerX + point.x * view.scale,
      y: view.centerY + point.z * view.scale,
    };
  }

  function roadWidth(kind, view) {
    const factor = clamp(view.scale / 0.333, 0.55, 1.8);
    const widths = [8.5, 6, 4];
    return Math.max(1.6, widths[kind] * factor);
  }

  function draw() {
    if (!el.canvas || state.width === 0) return;
    const city = state.city;
    const analysis = state.analysis;
    const view = makeView();
    state.view = view;
    const { width, height } = state;

    ctx.clearRect(0, 0, width, height);
    const background = ctx.createRadialGradient(width * 0.5, height * 0.35, 0, width * 0.5, height * 0.5, width * 0.75);
    background.addColorStop(0, '#132536');
    background.addColorStop(1, '#0a121a');
    ctx.fillStyle = background;
    ctx.fillRect(0, 0, width, height);

    if (!city) {
      ctx.fillStyle = '#93a8ba';
      ctx.font = '14px -apple-system, "PingFang SC", sans-serif';
      ctx.textAlign = 'center';
      ctx.fillText('缺少城市底图数据', width / 2, height / 2);
      return;
    }

    drawGrid(view);
    drawRoads(view);
    if (state.showCrowd && analysis) drawCrowding(view, analysis);
    if (analysis) {
      drawTaskOutline(view, analysis);
      drawTrajectory(view, analysis);
      if (state.showCheckpoints) drawCheckpoints(view, analysis);
      drawTaskMarkers(view, analysis);
    }
    drawScaleBar(view);
  }

  function drawGrid(view) {
    const step = 200;
    const halfWidth = view.mapWidth / 2;
    const halfHeight = view.mapHeight / 2;
    ctx.save();
    ctx.strokeStyle = 'rgba(94,132,163,0.13)';
    ctx.lineWidth = 1;
    ctx.beginPath();
    for (let x = -Math.floor(halfWidth / step) * step; x <= halfWidth; x += step) {
      const top = toScreen({ x, z: -halfHeight }, view);
      const bottom = toScreen({ x, z: halfHeight }, view);
      ctx.moveTo(top.x, top.y);
      ctx.lineTo(bottom.x, bottom.y);
    }
    for (let z = -Math.floor(halfHeight / step) * step; z <= halfHeight; z += step) {
      const left = toScreen({ x: -halfWidth, z }, view);
      const right = toScreen({ x: halfWidth, z }, view);
      ctx.moveTo(left.x, left.y);
      ctx.lineTo(right.x, right.y);
    }
    ctx.stroke();
    ctx.restore();
  }

  function drawRoads(view) {
    const city = state.city;
    ctx.save();
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    const groups = [[], [], []];
    for (const edge of city.edges) groups[edge[2]].push(edge);
    for (let kind = 2; kind >= 0; kind -= 1) {
      ctx.strokeStyle = kind === 0 ? '#2c455d' : kind === 1 ? '#233a4f' : '#1b2e40';
      ctx.lineWidth = roadWidth(kind, view);
      ctx.beginPath();
      for (const edge of groups[kind]) {
        const a = toScreen({ x: city.nodes[edge[0]][0], z: city.nodes[edge[0]][1] }, view);
        const b = toScreen({ x: city.nodes[edge[1]][0], z: city.nodes[edge[1]][1] }, view);
        ctx.moveTo(a.x, a.y);
        ctx.lineTo(b.x, b.y);
      }
      ctx.stroke();
    }
    ctx.restore();
  }

  function drawCrowding(view, analysis) {
    const city = state.city;
    const ceiling = Math.max(0.1, analysis.maxDensity);
    ctx.save();
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    for (const entry of analysis.edgeStats.values()) {
      const edge = city.edges[entry.edge];
      if (!edge) continue;
      const ratio = clamp(entry.maxDensity / ceiling, 0, 1);
      const color = lerpColor(CROWD_STOPS, ratio);
      const a = toScreen({ x: city.nodes[edge[0]][0], z: city.nodes[edge[0]][1] }, view);
      const b = toScreen({ x: city.nodes[edge[1]][0], z: city.nodes[edge[1]][1] }, view);
      ctx.globalAlpha = 0.28 + ratio * 0.6;
      ctx.strokeStyle = color;
      ctx.lineWidth = roadWidth(entry.kind >= 0 ? entry.kind : edge[2], view) * 1.05;
      ctx.beginPath();
      ctx.moveTo(a.x, a.y);
      ctx.lineTo(b.x, b.y);
      ctx.stroke();
      if (ratio > 0.35) {
        ctx.globalAlpha = 0.16;
        ctx.lineWidth = ctx.lineWidth * 2.4;
        ctx.stroke();
      }
    }
    ctx.globalAlpha = 1;
    ctx.restore();
  }

  function drawTaskOutline(view, analysis) {
    const points = [analysis.startPoint, analysis.pickupPoint, analysis.dropPoint].filter(Boolean);
    if (points.length < 2) return;
    ctx.save();
    ctx.strokeStyle = 'rgba(234,242,248,0.22)';
    ctx.lineWidth = 1.4;
    ctx.setLineDash([5, 7]);
    ctx.beginPath();
    points.forEach((point, index) => {
      const screen = toScreen(point, view);
      if (index === 0) ctx.moveTo(screen.x, screen.y);
      else ctx.lineTo(screen.x, screen.y);
    });
    ctx.stroke();
    ctx.restore();
  }

  function speedColor(speed, analysis) {
    const span = analysis.speedCeiling - analysis.speedFloor;
    const ratio = span <= 0 ? 0 : (speed - analysis.speedFloor) / span;
    return lerpColor(SPEED_STOPS, ratio);
  }

  function drawTrajectory(view, analysis) {
    const points = analysis.points;
    if (points.length < 2) return;
    const factor = clamp(view.scale / 0.333, 0.6, 2);
    ctx.save();
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';

    // 热力光晕：让速度高的路段在轨迹上自然发亮，而不是另画一张热力图。
    for (let i = 1; i < points.length; i += 1) {
      const from = toScreen(points[i - 1], view);
      const to = toScreen(points[i], view);
      const ratio = (points[i].speed - analysis.speedFloor) / Math.max(0.1, analysis.speedCeiling - analysis.speedFloor);
      const color = speedColor(points[i].speed, analysis);
      ctx.globalAlpha = 0.08 + clamp(ratio, 0, 1) * 0.16;
      ctx.strokeStyle = color;
      ctx.lineWidth = (7 + ratio * 9) * factor;
      ctx.beginPath();
      ctx.moveTo(from.x, from.y);
      ctx.lineTo(to.x, to.y);
      ctx.stroke();
    }

    ctx.globalAlpha = 1;
    for (let i = 1; i < points.length; i += 1) {
      const from = toScreen(points[i - 1], view);
      const to = toScreen(points[i], view);
      ctx.strokeStyle = speedColor(points[i].speed, analysis);
      ctx.lineWidth = 4.2 * factor;
      ctx.beginPath();
      ctx.moveTo(from.x, from.y);
      ctx.lineTo(to.x, to.y);
      ctx.stroke();
    }

    // 起点小箭头，帮助分辨行进方向。
    const first = toScreen(points[0], view);
    ctx.fillStyle = 'rgba(234,242,248,0.85)';
    ctx.beginPath();
    ctx.arc(first.x, first.y, 3.2 * factor, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();
  }

  function drawCheckpoints(view, analysis) {
    const factor = clamp(view.scale / 0.333, 0.65, 1.8);
    ctx.save();
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.font = `${Math.round(10 * factor)}px -apple-system, "PingFang SC", sans-serif`;
    const labelEvery = analysis.checkpoints.length > 10 ? 2 : 1;
    analysis.checkpoints.forEach((checkpoint, index) => {
      const screen = toScreen(checkpoint, view);
      const active = state.hover && state.hover.type === 'checkpoint' && state.hover.index === index;
      ctx.beginPath();
      ctx.arc(screen.x, screen.y, (active ? 7 : 4.6) * factor, 0, Math.PI * 2);
      ctx.fillStyle = active ? '#ffcf66' : '#ffffff';
      ctx.fill();
      ctx.lineWidth = 2 * factor;
      ctx.strokeStyle = '#0b141d';
      ctx.stroke();
      if (active) {
        ctx.beginPath();
        ctx.arc(screen.x, screen.y, 11 * factor, 0, Math.PI * 2);
        ctx.strokeStyle = '#ffcf66';
        ctx.lineWidth = 1.5;
        ctx.stroke();
      }
      if (index % labelEvery === 0 || active) {
        const label = formatTime(checkpoint.sec);
        const width = ctx.measureText(label).width + 8 * factor;
        const top = screen.y + 9 * factor;
        ctx.fillStyle = 'rgba(11,20,29,0.82)';
        roundRect(screen.x - width / 2, top, width, 15 * factor, 4 * factor);
        ctx.fill();
        ctx.fillStyle = active ? '#ffcf66' : '#dce8f2';
        ctx.fillText(label, screen.x, top + 7.7 * factor);
      }
    });
    ctx.restore();
  }

  function drawTaskMarkers(view, analysis) {
    const factor = clamp(view.scale / 0.333, 0.7, 1.8);
    const markers = [
      { point: analysis.startPoint, color: '#62e38b', label: '起点', shape: 'circle' },
      { point: analysis.pickupPoint, color: '#ffb02e', label: '取餐', shape: 'square' },
      { point: analysis.dropPoint, color: '#4fd6ff', label: '送达', shape: 'diamond' },
    ].filter((marker) => marker.point);

    ctx.save();
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.font = `600 ${Math.round(11 * factor)}px -apple-system, "PingFang SC", sans-serif`;
    for (const marker of markers) {
      const screen = toScreen(marker.point, view);
      const size = 8 * factor;
      ctx.beginPath();
      if (marker.shape === 'circle') {
        ctx.arc(screen.x, screen.y, size * 0.8, 0, Math.PI * 2);
      } else if (marker.shape === 'square') {
        ctx.rect(screen.x - size * 0.75, screen.y - size * 0.75, size * 1.5, size * 1.5);
      } else {
        ctx.moveTo(screen.x, screen.y - size);
        ctx.lineTo(screen.x + size, screen.y);
        ctx.lineTo(screen.x, screen.y + size);
        ctx.lineTo(screen.x - size, screen.y);
        ctx.closePath();
      }
      ctx.fillStyle = marker.color;
      ctx.fill();
      ctx.lineWidth = 2.2 * factor;
      ctx.strokeStyle = '#0b141d';
      ctx.stroke();

      const label = marker.label;
      const width = ctx.measureText(label).width + 10 * factor;
      const top = screen.y - size - 20 * factor;
      ctx.fillStyle = 'rgba(11,20,29,0.82)';
      roundRect(screen.x - width / 2, top, width, 16 * factor, 4 * factor);
      ctx.fill();
      ctx.fillStyle = marker.color;
      ctx.fillText(label, screen.x, top + 8.2 * factor);
    }
    ctx.restore();
  }

  function roundRect(x, y, width, height, radius) {
    const r = Math.min(radius, width / 2, height / 2);
    ctx.beginPath();
    ctx.moveTo(x + r, y);
    ctx.arcTo(x + width, y, x + width, y + height, r);
    ctx.arcTo(x + width, y + height, x, y + height, r);
    ctx.arcTo(x, y + height, x, y, r);
    ctx.arcTo(x, y, x + width, y, r);
    ctx.closePath();
  }

  function drawScaleBar(view) {
    const length = 200;
    const start = { x: -view.mapWidth / 2 + 80, z: view.mapHeight / 2 - 70 };
    const a = toScreen(start, view);
    const b = toScreen({ x: start.x + length, z: start.z }, view);
    ctx.save();
    ctx.strokeStyle = 'rgba(234,242,248,0.55)';
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    ctx.moveTo(a.x, a.y);
    ctx.lineTo(b.x, b.y);
    ctx.moveTo(a.x, a.y - 5);
    ctx.lineTo(a.x, a.y + 5);
    ctx.moveTo(b.x, b.y - 5);
    ctx.lineTo(b.x, b.y + 5);
    ctx.stroke();
    ctx.fillStyle = 'rgba(234,242,248,0.7)';
    ctx.font = '11px -apple-system, "PingFang SC", sans-serif';
    ctx.textAlign = 'left';
    ctx.textBaseline = 'bottom';
    ctx.fillText('200 米', a.x, a.y - 8);
    ctx.restore();
  }

  // ---------- 状态与交互 ----------

  function render() {
    renderStats();
    draw();
  }

  function renderStats() {
    const analysis = state.analysis;
    if (!analysis) {
      el.stats.innerHTML = '';
      return;
    }
    const rows = [
      ['用时', formatDuration(analysis.duration)],
      ['轨迹长度', `${Math.round(analysis.pathLength)} 米`],
      ['平均速度', `${analysis.avgSpeed.toFixed(1)} 米/秒`],
      ['最高速度', `${analysis.maxSpeed.toFixed(1)} 米/秒`],
      ['计时点', `${analysis.checkpoints.length} 个`],
      ['道路拥挤峰值', `${analysis.maxDensity.toFixed(1)} 辆/百米`],
      ['结果', resultText(analysis.finishEvent)],
    ];
    el.stats.innerHTML = rows
      .map(([label, value]) => `<dt>${label}</dt><dd>${value}</dd>`)
      .join('');
  }

  function roadText(checkpoint) {
    const city = state.city;
    if (!city || !(checkpoint.road >= 0) || !city.edges[checkpoint.road]) {
      return '当前道路：未记录';
    }
    const edge = city.edges[checkpoint.road];
    const length = Math.max(1, edgeLength(city, edge));
    const density = (checkpoint.cars / length) * 100;
    const kind = KIND_NAMES[checkpoint.rk] || KIND_NAMES[edge[2]] || '道路';
    return [
      `当前道路：<strong>${kind}</strong>（路段 ${checkpoint.road}）`,
      `同一路段车辆 <strong>${checkpoint.cars}</strong> 辆 · 行人 ${checkpoint.peds} 人`,
      `80 米内车辆 ${checkpoint.near} 辆 · ${density.toFixed(1)} 辆/百米`,
    ].join('<br>');
  }

  function showHover(hover, screenPoint) {
    state.hover = hover;
    if (!hover) {
      el.tooltip.hidden = true;
      el.roadInfo.textContent = '点击计时点或轨迹上的位置查看。';
      draw();
      return;
    }
    const checkpoint = hover.checkpoint;
    el.tooltip.hidden = false;
    el.tooltip.style.left = `${screenPoint.x}px`;
    el.tooltip.style.top = `${screenPoint.y}px`;
    el.tooltip.innerHTML = [
      `<strong>${hover.title}</strong>`,
      `速度 ${checkpoint.speed.toFixed(1)} 米/秒 · 剩余 ${formatTime(checkpoint.left)}`,
      checkpoint.road >= 0 ? `路段 ${checkpoint.road} · ${checkpoint.cars} 车 / ${checkpoint.peds} 人` : '道路未记录',
    ].join('<br>');
    el.roadInfo.innerHTML = roadText(checkpoint);
    draw();
  }

  function hitTest(px, py) {
    if (!state.analysis || !state.view) return null;
    const view = state.view;
    const candidates = [];
    state.analysis.checkpoints.forEach((checkpoint, index) => {
      if (!state.showCheckpoints) return;
      const screen = toScreen(checkpoint, view);
      candidates.push({
        type: 'checkpoint',
        index,
        distance: distance2({ x: px, y: py }, screen),
        screen,
        checkpoint,
        title: `计时点 ${formatTime(checkpoint.sec)}`,
      });
    });
    const markers = [
      { point: state.analysis.startPoint, title: '任务起点' },
      { point: state.analysis.pickupPoint, title: '取餐点' },
      { point: state.analysis.dropPoint, title: '送达点' },
    ];
    for (const marker of markers) {
      if (!marker.point) continue;
      const screen = toScreen(marker.point, view);
      const nearest = state.analysis.points.reduce((best, point) => {
        const distance = Math.hypot(point.x - marker.point.x, point.z - marker.point.z);
        return !best || distance < best.distance ? { point, distance } : best;
      }, null);
      const checkpoint = nearest
        ? { ...nearest.point, sec: (nearest.point.t - (state.analysis.points[0] ? state.analysis.points[0].t : 0)) / 1000 }
        : { speed: 0, left: 0, road: -1, cars: 0, peds: 0, near: 0 };
      candidates.push({
        type: 'marker',
        index: -1,
        distance: distance2({ x: px, y: py }, screen),
        screen,
        checkpoint,
        title: marker.title,
      });
    }
    const threshold = 18;
    const nearby = candidates
      .filter((candidate) => candidate.distance <= threshold)
      .sort((a, b) => a.distance - b.distance);
    return nearby[0] || nearestPoint(px, py, threshold);
  }

  function nearestPoint(px, py, threshold) {
    const view = state.view;
    let best = null;
    for (const point of state.analysis.points) {
      const screen = toScreen(point, view);
      const distance = distance2({ x: px, y: py }, screen);
      if (!best || distance < best.distance) {
        best = {
          type: 'point',
          index: -1,
          distance,
          screen,
          checkpoint: {
            ...point,
            sec: (point.t - (state.analysis.points[0] ? state.analysis.points[0].t : 0)) / 1000,
          },
          title: '轨迹位置',
        };
      }
    }
    return best && best.distance <= threshold ? best : null;
  }

  function onPointer(event) {
    const rect = el.canvas.getBoundingClientRect();
    const px = event.clientX - rect.left;
    const py = event.clientY - rect.top;
    showHover(hitTest(px, py), { x: px, y: py });
  }

  // ---------- 载入与下载 ----------

  function sessionLabel(session, index) {
    const finish = (session.events || []).find((event) => event.n === 'finish');
    const seconds = finish && finish.p && Number.isFinite(Number(finish.p.sec))
      ? Number(finish.p.sec)
      : (() => {
          const positions = (session.events || []).filter((event) => event.n === 'pos');
          return positions.length ? (positions[positions.length - 1].t - positions[0].t) / 1000 : 0;
        })();
    return `${state.data.meta && state.data.meta.demo ? '示例 ' : ''}${index + 1} · ${formatTime(seconds)} · ${resultText(finish)}`;
  }

  function loadData(data) {
    if (!data || !Array.isArray(data.sessions) || data.sessions.length === 0) {
      throw new Error('数据里没有 sessions');
    }
    state.data = data;
    el.sessionSelect.innerHTML = data.sessions
      .map((session, index) => `<option value="${index}">${sessionLabel(session, index)}</option>`)
      .join('');
    el.sessionSelect.value = '0';
    el.demoBadge.hidden = !(data.meta && data.meta.demo);
    selectSession(0);
    updateMetaLine();
  }

  function selectSession(index) {
    state.session = state.data.sessions[index];
    state.analysis = analyze(state.session);
    state.hover = null;
    el.tooltip.hidden = true;
    el.roadInfo.textContent = '点击计时点或轨迹上的位置查看。';
    render();
  }

  function updateMetaLine() {
    const meta = state.data.meta || {};
    const city = state.city;
    const parts = [];
    parts.push(meta.label || '行为记录');
    parts.push(`${state.data.sessions.length} 个会话`);
    if (city) parts.push(`地图种子 ${city.seed} · ${city.nodes.length} 个路网节点`);
    if (city && meta.city != null && Number(meta.city) !== Number(city.seed)) {
      parts.push(`注意：数据来自种子 ${meta.city}，当前底图是 ${city.seed}`);
    }
    el.metaLine.textContent = parts.join(' · ');
    el.dataNote.textContent = meta.demo
      ? '当前展示的是演示轨迹，不是真实访客数据。真实数据可用 tools/build_behavior_page_data.py 从导出 CSV 生成后，用「载入数据」打开。'
      : `生成时间 ${meta.generated_at || '未知'}。轨迹和道路密度均来自导出的 behavior_events 事件。`;
  }

  function download(name, blob) {
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = name;
    document.body.appendChild(link);
    link.click();
    link.remove();
    setTimeout(() => URL.revokeObjectURL(url), 1500);
  }

  function dateStamp() {
    return new Date().toISOString().slice(0, 10);
  }

  function exportJson() {
    if (!state.data) return;
    const payload = { meta: state.data.meta || {}, sessions: state.data.sessions };
    download(
      `behavior-sessions-${dateStamp()}.json`,
      new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json' })
    );
  }

  function csvCell(value) {
    const text = String(value == null ? '' : value);
    return `"${text.replace(/"/g, '""')}"`;
  }

  function exportCsv() {
    if (!state.data) return;
    const lines = ['session_id,event_name,t_ms,props'];
    for (const session of state.data.sessions) {
      for (const event of session.events || []) {
        lines.push(
          [
            csvCell(session.id || ''),
            csvCell(event.n || ''),
            Number.isFinite(Number(event.t)) ? Math.round(Number(event.t)) : 0,
            csvCell(JSON.stringify(event.p || {})),
          ].join(',')
        );
      }
    }
    const blob = new Blob(['﻿' + lines.join('\r\n')], { type: 'text/csv;charset=utf-8' });
    download(`behavior-events-${dateStamp()}.csv`, blob);
  }

  function exportPng() {
    if (!el.canvas) return;
    el.canvas.toBlob((blob) => {
      if (blob) download(`behavior-map-${dateStamp()}.png`, blob);
    }, 'image/png');
  }

  async function onFile(event) {
    const file = event.target.files && event.target.files[0];
    if (!file) return;
    try {
      const text = await file.text();
      const data = JSON.parse(text);
      loadData(data);
    } catch (error) {
      el.metaLine.textContent = `载入失败：${error.message}`;
    } finally {
      event.target.value = '';
    }
  }

  function bind() {
    el.sessionSelect.addEventListener('change', () => selectSession(Number(el.sessionSelect.value)));
    el.toggleCrowd.addEventListener('change', () => {
      state.showCrowd = el.toggleCrowd.checked;
      draw();
    });
    el.toggleCheckpoints.addEventListener('change', () => {
      state.showCheckpoints = el.toggleCheckpoints.checked;
      draw();
    });
    el.fileInput.addEventListener('change', onFile);
    el.downloadJson.addEventListener('click', exportJson);
    el.downloadCsv.addEventListener('click', exportCsv);
    el.downloadPng.addEventListener('click', exportPng);
    el.canvas.addEventListener('pointermove', onPointer);
    el.canvas.addEventListener('pointerdown', onPointer);
    el.canvas.addEventListener('pointerleave', () => showHover(null));
    window.addEventListener('resize', resize);
  }

  // ---------- 启动 ----------

  try {
    if (!CITY) throw new Error('缺少城市底图 data/sample-data.js');
    state.city = CITY;
    bind();
    loadData(window.SWM_SAMPLE || { sessions: [] });
    resize();
  } catch (error) {
    el.metaLine.textContent = `页面初始化失败：${error.message}`;
    el.stats.innerHTML = '';
  }
})();
