'use strict';
// Skylt (COMPUTER_TYPE=signage med SIGN_SHELL=true): sidor som visas i tur och ordning, utan någon inmatning.
// Ren logik som testas med node --test: tolkning av SIGN_PAGES och vilken sida som står på tur.

const MIN_S = 5;
const MAX_S = 3600;
const MAX_PAGES = 36;

function clamp(s, def) {
  const n = parseInt(s, 10);
  return Number.isFinite(n) ? Math.max(MIN_S, Math.min(MAX_S, n)) : def;
}

function httpsUrl(v) {
  try {
    const u = new URL(String(v || '').trim());
    return u.protocol === 'https:' && u.hostname ? u.href : '';
  } catch (e) { return ''; }
}

/**
 * SIGN_PAGES: en JSON-lista [{"url":"https://…","s":30}] eller en rad per sida "https://adress|sekunder" (rader skiljs av
 * radbrytning eller den bokstavliga \n, som i .config). Ogiltiga poster (inte https) hoppas över. Utan sekunder gäller
 * defaultSeconds. Utan sidor (eller utan giltiga) används fallbackUrl (första Startsidan) om den är en https-adress.
 */
function parseSignPages(raw, defaultSeconds, fallbackUrl) {
  const def = clamp(defaultSeconds, 30);
  const out = [];
  const add = (url, s) => {
    const u = httpsUrl(url);
    if (u && out.length < MAX_PAGES) out.push({ url: u, seconds: clamp(s, def) });
  };
  const text = String(raw || '').trim();
  if (text.startsWith('[')) {
    try {
      const list = JSON.parse(text);
      if (Array.isArray(list)) for (const o of list) if (o && typeof o === 'object') add(o.url, o.s);
    } catch (e) { /* tolkas som rader */ }
  }
  if (!out.length && text && !text.startsWith('[')) {
    const lines = text.includes('\n') ? text.split(/\r?\n/) : text.split('\\n');
    for (const line of lines) {
      if (!line.trim()) continue;
      const i = line.lastIndexOf('|');
      if (i > 0 && /^\s*\d+\s*$/.test(line.slice(i + 1))) add(line.slice(0, i), line.slice(i + 1));
      else add(line, undefined);
    }
  }
  if (!out.length) {
    const f = httpsUrl(fallbackUrl);
    if (f) out.push({ url: f, seconds: def });
  }
  return out;
}

/** Nästa sida i tur och ordning (börjar om efter den sista) */
function nextIndex(i, count) {
  return count > 0 ? (i + 1) % count : 0;
}

module.exports = { parseSignPages, nextIndex, MIN_S, MAX_S, MAX_PAGES };
