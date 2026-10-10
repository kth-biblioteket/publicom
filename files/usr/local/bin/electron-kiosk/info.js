'use strict';
// Förstasidans nederkant: text som hämtas från webbadresser (informationsfält och meddelanderad).
// Adresserna hämtas av skalet självt, bara över https mot en tillåten värd (samma regel som för navigeringen),
// utan omdirigeringar, och visas alltid som ren text, aldrig som HTML. Texten ligger kvar om nätet försvinner
// och byts efter en timme utan svar mot ett streck (fält) eller ingen rad (meddelande).
const https = require('https');

const STALE_MS = 60 * 60 * 1000;
const MAX_BYTES = 2048;
const MAX_LENGTH = 300;
const TIMEOUT_MS = 5000;

/** Ren text: kontrolltecken bort, radbrytningar som blanksteg, högst 300 tecken */
function clean(raw) {
  const s = String(raw || '').replace(/[\u0000-\u0009\u000b-\u001f\u007f-\u009f]/g, '').replace(/\s*\n\s*/g, ' ').trim();
  return s.length > MAX_LENGTH ? s.slice(0, MAX_LENGTH) : s;
}

/** Hämtar en https-adress som text. Null vid fel, annan status än 200, omdirigering eller för långsamt svar. */
function fetchText(address) {
  return new Promise((resolve) => {
    let done = false;
    const finish = (v) => { if (!done) { done = true; resolve(v); } };
    let req;
    try {
      req = https.get(address, { timeout: TIMEOUT_MS, headers: { Accept: 'text/plain' } }, (res) => {
        if (res.statusCode !== 200) { res.resume(); finish(null); return; }
        const chunks = [];
        let size = 0;
        res.on('data', (c) => {
          size += c.length;
          chunks.push(c);
          if (size >= MAX_BYTES) { res.destroy(); finish(clean(Buffer.concat(chunks).subarray(0, MAX_BYTES).toString('utf8'))); }
        });
        res.on('end', () => finish(clean(Buffer.concat(chunks).toString('utf8'))));
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
    await Promise.all(this.urls().filter((u) => this.policy.allows(u)).map(async (u) => {
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
    return { fields, message: text ? { text, style: s.message.style } : null };
  }
}

module.exports = { InfoFeed, fetchText, clean, STALE_MS, MAX_LENGTH };
