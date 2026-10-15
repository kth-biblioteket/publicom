'use strict';
// Sekunder sedan senaste riktiga inmatning (mus, tangentbord, tryck), från visit_tracker.py som läser kärnans inmatningsenheter.
// En film, skärmsläckaren eller en VNC-klient nollställer inte den tiden, men X:s inaktivitetsräknare (powerMonitor) gör det.
// Ren funktion som testas med node --test. Null om filen saknas eller är oläsbar (då används X:s räknare).
const fs = require('fs');

function parse(text, nowSec) {
  const t = parseInt(String(text).trim(), 10);
  if (!Number.isFinite(t) || t <= 0 || t > nowSec + 60) return null;
  return Math.max(0, nowSec - t);
}

function inputIdleSeconds(file, nowMs) {
  try { return parse(fs.readFileSync(file, 'utf8'), Math.floor((nowMs || Date.now()) / 1000)); } catch (e) { return null; }
}

module.exports = { inputIdleSeconds, parse };
