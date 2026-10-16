'use strict';
// Skylt (COMPUTER_TYPE=signage): sidor som visas i tur och ordning, utan någon inmatning, med ett schema som väljer spellista efter tid.
// Ren logik som testas med node --test: tolkning av SIGN_PAGES och SIGN_SCHEDULE, vilken lista som gäller nu och vilken sida som står på tur.

const MIN_S = 5;
const MAX_S = 3600;
const MAX_PAGES = 36;

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;
const isDate = (v) => typeof v === 'string' && ISO_DATE.test(v);

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
 * SIGN_PAGES: en JSON-lista [{"url":"https://…","s":30,"start":"2026-10-20","end":"2026-10-31"}] (start och end valfria, inklusive) eller en rad per sida "https://adress|sekunder" (rader skiljs av
 * radbrytning eller den bokstavliga \n, som i .config). Ogiltiga poster (inte https) hoppas över. Utan sekunder gäller
 * defaultSeconds. Utan sidor (eller utan giltiga) används fallbackUrl (första Startsidan) om den är en https-adress.
 */
function parseSignPages(raw, defaultSeconds, fallbackUrl) {
  const def = clamp(defaultSeconds, 30);
  const out = [];
  const add = (url, s, start, end) => {
    const u = httpsUrl(url);
    if (!u || out.length >= MAX_PAGES) return;
    const page = { url: u, seconds: clamp(s, def) };
    // start och end (YYYY-MM-DD, båda inklusive) är valfria; ett ogiltigt datum ignoreras (ingen gräns)
    if (isDate(start)) page.start = start;
    if (isDate(end)) page.end = end;
    out.push(page);
  };
  const text = String(raw || '').trim();
  if (text.startsWith('[')) {
    try {
      const list = JSON.parse(text);
      if (Array.isArray(list)) for (const o of list) if (o && typeof o === 'object') add(o.url, o.s, o.start, o.end);
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

// ---------- schema (SIGN_SCHEDULE) ----------

const HHMM = /^(\d{1,2}):(\d{2})$/;
const ISO = /^\d{4}-\d{2}-\d{2}$/;

/** "HH:MM" till minuter från midnatt ("24:00" = 1440); null om ogiltig */
function minutes(v) {
  const m = HHMM.exec(String(v));
  if (!m) return null;
  const h = parseInt(m[1], 10), mi = parseInt(m[2], 10);
  if (mi > 59 || h > 24 || (h === 24 && mi !== 0)) return null;
  return h * 60 + mi;
}

/**
 * SIGN_SCHEDULE: {"lists":{"Dag":[{"url":"https://…","s":30}]},"slots":[{"list":"Dag","days":[1..7],"from":"08:00","to":"19:00","dates":["2026-10-20","2026-10-31"]}],"off":false}.
 * Returnerar { lists: {namn: [{url, seconds}]}, slots: [...giltiga], off } eller null om texten saknas eller inte går att läsa.
 * En rad med okänd lista, från senare än till eller ogiltiga dagar, tider eller datum hoppas över.
 */
function parseSchedule(raw, defaultSeconds) {
  let o;
  try { o = JSON.parse(String(raw || '').trim()); } catch (e) { return null; }
  if (!o || typeof o !== 'object' || Array.isArray(o)) return null;
  const lists = {};
  for (const [name, pages] of Object.entries(o.lists && typeof o.lists === 'object' ? o.lists : {})) {
    lists[name] = parseSignPages(JSON.stringify(Array.isArray(pages) ? pages : []), defaultSeconds, '');
  }
  // periods: {"Jul": ["2026-12-01","2027-01-06"]}, inklusive och får gå över årsskiftet. En lista utan period gäller alltid.
  const periods = {};
  for (const [name, r] of Object.entries(o.periods && typeof o.periods === 'object' && !Array.isArray(o.periods) ? o.periods : {})) {
    if (Array.isArray(r) && r.length === 2 && isDate(r[0]) && isDate(r[1]) && r[0] <= r[1]) periods[name] = [r[0], r[1]];
  }
  const slots = [];
  for (const sl of Array.isArray(o.slots) ? o.slots : []) {
    if (!sl || typeof sl !== 'object' || !Object.prototype.hasOwnProperty.call(lists, sl.list)) continue;
    const slot = { list: sl.list };
    if (sl.days !== undefined) {
      if (!Array.isArray(sl.days) || !sl.days.every((d) => Number.isInteger(d) && d >= 1 && d <= 7)) continue;
      slot.days = sl.days;
    }
    const from = sl.from === undefined ? null : minutes(sl.from);
    const to = sl.to === undefined ? null : minutes(sl.to);
    if ((sl.from !== undefined && from === null) || (sl.to !== undefined && to === null)) continue;
    if (from !== null && to !== null && from > to) continue;
    if (from !== null) slot.from = from;
    if (to !== null) slot.to = to;
    if (sl.dates !== undefined) {
      if (!Array.isArray(sl.dates) || !sl.dates.length || !sl.dates.every((d) => ISO.test(String(d)))) continue;
      slot.dates = [String(sl.dates[0]), String(sl.dates[sl.dates.length - 1])];
      if (slot.dates[0] > slot.dates[1]) continue;
    }
    slots.push(slot);
  }
  return { lists, periods, slots, off: o.off === true };
}

const pad2 = (n) => String(n).padStart(2, '0');

/** Enhetens dag som YYYY-MM-DD (datorns tidszon, Europe/Stockholm) */
const dateOf = (now) => `${now.getFullYear()}-${pad2(now.getMonth() + 1)}-${pad2(now.getDate())}`;

/** Gäller sidan i dag? start och end inklusive, ett saknat fält = ingen gräns */
function pageOn(page, now) {
  const d = dateOf(now);
  return !(page.start && d < page.start) && !(page.end && d > page.end);
}

/** Gäller listans period i dag? En lista utan period gäller alltid */
function listOn(schedule, name, now) {
  const r = schedule.periods && schedule.periods[name];
  if (!r) return true;
  const d = dateOf(now);
  return d >= r[0] && d <= r[1];
}

/** Standardlistan i dag: de sidor som gäller, annars reservsidan (första Startsidan) som för en tom lista */
function standardPages(pages, fallback, now) {
  const on = pages.filter((p) => pageOn(p, now));
  return on.length ? on : fallback;
}

/** Gäller raden nu? Veckodag 1-7 (mån-sön), från (inklusive) till till (exklusive), datum inklusive båda ändarna; ett saknat fält = alltid */
function slotMatches(slot, now) {
  const day = ((now.getDay() + 6) % 7) + 1;
  const min = now.getHours() * 60 + now.getMinutes();
  const date = dateOf(now);
  if (slot.days && !slot.days.includes(day)) return false;
  if (slot.from !== undefined && min < slot.from) return false;
  if (slot.to !== undefined && min >= slot.to) return false;
  if (slot.dates && (date < slot.dates[0] || date > slot.dates[1])) return false;
  return true;
}

/**
 * Vilken spellista som gäller just nu: bland raderna som gäller vinner den första med "dates", annars den första utan.
 * Ingen rad (eller en lista utan sidor) ger { name: '', pages: null, off } där off är true bara om ingen rad gällde och "off" är satt.
 * Annars { name, pages }.
 */
function activeList(schedule, now) {
  if (!schedule) return { name: '', pages: null, off: false };
  // En rad vars spellista har en period som inte gäller i dag hoppas över, som en okänd lista
  const matching = schedule.slots.filter((s) => slotMatches(s, now) && listOn(schedule, s.list, now));
  const slot = matching.find((s) => s.dates) || matching[0];
  if (!slot) return { name: '', pages: null, off: schedule.off };
  const pages = schedule.lists[slot.list].filter((p) => pageOn(p, now));
  return pages && pages.length ? { name: slot.list, pages, off: false } : { name: '', pages: null, off: false };
}

module.exports = { parseSignPages, parseSchedule, activeList, slotMatches, pageOn, listOn, standardPages, nextIndex, MIN_S, MAX_S, MAX_PAGES };
