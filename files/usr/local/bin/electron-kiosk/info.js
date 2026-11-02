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
 * Textblock från Polopoly (kth.se): <article class="… kthb-alert-info …" data-cid="1.1505584">text och länk</article> någonstans på sidan,
 * hittat på sitt data-cid. Returnerar { text, style } (style warning = gul, success = grön eller alert = röd, annars null),
 * eller null om cid saknas eller sidan inte har blocket. Länkar tas bort tillsammans med sin text.
 */
function parseAlert(html, cid) {
  if (!cid) return null;
  const src = String(html || '');
  const re = /<article\b([^>]*)>/gi;
  let open;
  while ((open = re.exec(src))) {
    const attrs = open[1];
    const c = /\bclass="([^"]*)"/i.exec(attrs);
    const classes = c ? c[1] : '';
    // Blocket med det id:t, vilken sorts block som helst; klassen kthb-alert-… ger bara färgen
    const match = new RegExp('\\bdata-cid="' + cid.replace(/\./g, '\\.') + '"', 'i').test(attrs);
    if (!match) continue;
    const end = src.toLowerCase().indexOf('</article>', open.index);
    if (end < 0) return null;
    const k = /\bkthb-alert-([a-z]+)\b/i.exec(classes);
    const kind = k ? k[1].toLowerCase() : '';
    // KTH:s färger: info är gul (blå finns inte), success grön och danger röd. Okänd typ: inställningens färg (null)
    const style = ['info', 'warning', 'warn'].includes(kind) ? 'warning' : kind === 'success' ? 'success' : ['alert', 'danger', 'error'].includes(kind) ? 'alert' : null;
    // Länkar (med sin text) tas bort: de går inte att trycka på i en kiosk, och en text som slutar på "Läs mer" vore missvisande
    const body = src.slice(open.index + open[0].length, end).replace(/<a\b[^>]*>[\s\S]*?<\/a>/gi, ' ');
    return { text: htmlToText(body), style };
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
    for (const m of [this.settings.message.url, this.settings.message.urlEn]) if (m && !list.includes(m)) list.push(m);
    return list;
  }

  /** Hämtar alla adresser som tillåts. Misslyckade hämtningar lämnar den senaste texten kvar. */
  async refresh() {
    // Bara med ett Polopoly-id hämtas meddelandet som webbsida; LAUNCHER_MESSAGE_URL är som förut ren text
    const cid = this.settings.message.cid;
    const msgUrls = cid ? [this.settings.message.url, this.settings.message.urlEn].filter(Boolean) : [];
    await Promise.all(this.urls().filter((u) => this.policy.allows(u)).map(async (u) => {
      if (msgUrls.includes(u)) { // Polopoly-blocket på kth.se (LAUNCHER_POLOPOLY_ID)
        const raw = await this.fetchFn(u, { page: true });
        if (raw === null) return;
        const a = parseAlert(raw, cid);
        // Ingen sida eller inget block (t.ex. avpublicerat): ingen rad, aldrig rå HTML
        this.cache.set(u, { text: a ? a.text : '', style: a && a.style, at: this.now() });
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
    // Från adressen: engelska adressen för English (om den inte gav någon text används den svenska), annars den svenska
    let from = s.message.url ? this.cache.get(s.message.url) : null;
    if (english && s.message.urlEn) {
      const en = this.cache.get(s.message.urlEn);
      if (en && this.now() - en.at <= STALE_MS && en.text) from = en;
    }
    const fromUrl = from && this.now() - from.at <= STALE_MS ? from.text : null;
    if (fromUrl !== null) text = fromUrl;
    const c = fromUrl !== null ? from : null;
    const style = c && c.style ? c.style : s.message.style; // blockets egen färg om sidan anger den
    return { fields, message: text ? { text, style, icon: s.message.icon } : null };
  }
}

module.exports = { InfoFeed, fetchText, clean, htmlToText, parseAlert, STALE_MS, MAX_LENGTH };
