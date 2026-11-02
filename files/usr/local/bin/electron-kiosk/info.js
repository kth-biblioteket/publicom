'use strict';
// Förstasidans nederkant: text som hämtas från webbadresser (informationsfält och meddelanderad).
// Adresserna hämtas av skalet självt, bara över https mot en tillåten värd (samma regel som för navigeringen),
// utan omdirigeringar, och visas alltid som ren text, aldrig som HTML. Texten ligger kvar om nätet försvinner
// och byts efter en timme utan svar mot ett streck (fält) eller ingen rad (meddelande).
const https = require('https');

const STALE_MS = 60 * 60 * 1000;
const MAX_BYTES = 2048;
const MAX_PAGE_BYTES = 512 * 1024; // en hel webbsida (meddelande från kth.se) hämtas till den här storleken
const MAX_LENGTH = 300;
const TIMEOUT_MS = 5000;

/** Ren text: kontrolltecken bort, radbrytningar som blanksteg, högst 300 tecken */
function clean(raw) {
  const s = String(raw || '').replace(/[\u0000-\u0009\u000b-\u001f\u007f-\u009f]/g, '').replace(/\s*\n\s*/g, ' ').trim();
  return s.length > MAX_LENGTH ? s.slice(0, MAX_LENGTH) : s;
}

const ENTITIES = { nbsp: ' ', amp: '&', lt: '<', gt: '>', quot: '"', apos: "'" };

/** Ren text ur HTML: skript, stilar och taggar bort, tecknen &nbsp; &amp; &#228; m.fl. tolkade, blanksteg hopdragna. Aldrig HTML ut. */
function htmlToText(html) {
  const text = String(html || '')
    .replace(/<(script|style)[\s\S]*?<\/\1>/gi, ' ')
    .replace(/<!--[\s\S]*?-->/g, ' ')
    .replace(/<\/?(p|br|div|li|ul|ol|h[1-6]|tr|td|th|table|section|article|header|footer)\b[^>]*>/gi, ' ') // blocktaggar ger blanksteg
    .replace(/<[^>]*>/g, '')                                                                                  // inline-taggar (b, span, a …) bara bort
    .replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (m, e) => {
      if (e[0] === '#') {
        const n = e[1].toLowerCase() === 'x' ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10);
        return Number.isFinite(n) && n > 0 && n < 0x110000 ? String.fromCodePoint(n) : ' ';
      }
      return Object.prototype.hasOwnProperty.call(ENTITIES, e.toLowerCase()) ? ENTITIES[e.toLowerCase()] : m;
    });
  return clean(text.replace(/[\u00a0\s]+/g, ' '));
}

/**
 * Meddelandeblock från kth.se/biblioteket: <article class="… kthb-alert kthb-alert-info …">text och länk</article> någonstans på sidan.
 * Returnerar { text, style } (style info, warning eller alert, annars null) för det första blocket, eller null om sidan inte har något.
 * Länkens text ingår i texten; länken själv följs inte.
 */
function parseAlert(html, cid) {
  const src = String(html || '');
  const re = /<article\b([^>]*)>/gi;
  let open;
  while ((open = re.exec(src))) {
    const attrs = open[1];
    const c = /\bclass="([^"]*)"/i.exec(attrs);
    const classes = c ? c[1] : '';
    // Med cid: blocket med det id:t (vilken sorts block som helst). Utan: det första blocket med klassen kthb-alert.
    const match = cid ? new RegExp('\\bdata-cid="' + cid.replace(/\./g, '\\.') + '"', 'i').test(attrs) : /\bkthb-alert\b/.test(classes);
    if (!match) continue;
    const end = src.toLowerCase().indexOf('</article>', open.index);
    if (end < 0) return null;
    const k = /\bkthb-alert-([a-z]+)\b/i.exec(classes);
    const kind = k ? k[1].toLowerCase() : '';
    const style = kind === 'info' ? 'info' : kind === 'warning' || kind === 'warn' ? 'warning' : ['alert', 'danger', 'error'].includes(kind) ? 'alert' : null;
    return { text: htmlToText(src.slice(open.index + open[0].length, end)), style };
  }
  return null;
}

/** Hämtar en https-adress som text. Null vid fel, annan status än 200, omdirigering eller för långsamt svar. */
function fetchText(address, opts = {}) {
  const limit = opts.page ? MAX_PAGE_BYTES : MAX_BYTES;
  const accept = opts.page ? 'text/html, text/plain' : 'text/plain';
  const finishText = (buf) => (opts.page ? buf.toString('utf8') : clean(buf.toString('utf8')));
  return new Promise((resolve) => {
    let done = false;
    const finish = (v) => { if (!done) { done = true; resolve(v); } };
    let req;
    try {
      req = https.get(address, { timeout: TIMEOUT_MS, headers: { Accept: accept } }, (res) => {
        if (res.statusCode !== 200) { res.resume(); finish(null); return; }
        const chunks = [];
        let size = 0;
        res.on('data', (c) => {
          size += c.length;
          chunks.push(c);
          if (size >= limit) { res.destroy(); finish(finishText(Buffer.concat(chunks).subarray(0, limit))); }
        });
        res.on('end', () => finish(finishText(Buffer.concat(chunks))));
        res.on('error', () => finish(null));
        res.on('aborted', () => finish(null));
      });
    } catch (e) { finish(null); return; }
    req.on('timeout', () => { req.destroy(); finish(null); });
    req.on('error', () => finish(null));
  });
}

class InfoFeed {
  /** fetchFn och now kan bytas ut i tester */
  constructor(settings, policy, fetchFn = fetchText, now = Date.now) {
    this.settings = settings;
    this.policy = policy;
    this.fetchFn = fetchFn;
    this.now = now;
    this.cache = new Map();
  }

  urls() {
    const list = [];
    for (const f of this.settings.fields) if (f.type === 'url' && !list.includes(f.value)) list.push(f.value);
    const m = this.settings.message.url;
    if (m && !list.includes(m)) list.push(m);
    return list;
  }

  /** Hämtar alla adresser som tillåts. Misslyckade hämtningar lämnar den senaste texten kvar. */
  async refresh() {
    const msgUrl = this.settings.message.url;
    await Promise.all(this.urls().filter((u) => this.policy.allows(u)).map(async (u) => {
      if (u === msgUrl) { // meddelandet kan vara ren text eller en webbsida med ett kthb-alert-block
        const raw = await this.fetchFn(u, { page: true });
        if (raw === null) return;
        const html = /<(!doctype|html|article|body)\b/i.test(raw);
        const a = html ? parseAlert(raw, this.settings.message.cid) : null;
        // En webbsida utan block (t.ex. avpublicerat) visas aldrig som text: ingen rad
        this.cache.set(u, { text: html ? (a ? a.text : '') : clean(raw), style: a && a.style, at: this.now() });
        return;
      }
      const text = await this.fetchFn(u);
      if (text !== null) this.cache.set(u, { text, at: this.now() });
    }));
  }

  fresh(url, fallback) {
    const c = this.cache.get(url);
    return !c || this.now() - c.at > STALE_MS ? fallback : c.text;
  }

  /** Det förstasidan visar: fält (med färdig text) och meddelanderad, på valt språk */
  view(english) {
    const s = this.settings;
    const fields = s.fields.map((f) => ({
      type: f.type,
      label: f.labelFor(english),
      value: f.type === 'text' ? f.value : (f.type === 'url' ? this.fresh(f.value, '–') : ''),
    }));
    // Meddelandet: en text från adressen visas. Tom text därifrån döljer raden. Inget (färskt) svar ger den fasta texten.
    let text = english && s.message.textEn ? s.message.textEn : s.message.text;
    const fromUrl = s.message.url ? this.fresh(s.message.url, null) : null;
    if (fromUrl !== null) text = fromUrl;
    const c = s.message.url ? this.cache.get(s.message.url) : null;
    const style = fromUrl !== null && c && c.style ? c.style : s.message.style; // blockets egen färg om sidan anger den
    return { fields, message: text ? { text, style, icon: s.message.icon } : null };
  }
}

module.exports = { InfoFeed, fetchText, clean, htmlToText, parseAlert, STALE_MS, MAX_LENGTH };
