'use strict';
// Vilken tjänst som är öppen, för användningsstatistiken (visit_tracker.py läser filen när ett besök slutar).
// Varje byte av aktiv tjänst blir en rad {t: epoch-sekunder, url, name}; på förstasidan är url och name tomma.
// Bara tjänstens konfigurerade adress (APPS, inte den engelska) och namn skrivs, aldrig sidor eller andra adresser.
// Filen skrivs om i sin helhet (en skrivare, atomiskt), så att den inte växer och inget delvis skrivet läses.
const fs = require('fs');

const MAX_EVENTS = 2000;
const MAX_AGE_S = 3 * 24 * 3600;

class UsageLog {
  constructor(file, now) {
    this.file = file;
    this.now = now || (() => Date.now() / 1000);
    this.events = [];
  }

  /** Tjänsten som nu är aktiv ('' = förstasidan). Samma tjänst två gånger i rad skrivs inte om. */
  record(url, name) {
    const u = String(url || '').slice(0, 500);
    const n = String(name || '').slice(0, 100);
    const last = this.events[this.events.length - 1];
    if (last && last.url === u) return;
    const t = Math.floor(this.now());
    this.events.push({ t, url: u, name: u ? n : '' });
    const cutoff = t - MAX_AGE_S;
    // Behåll tillståndet före gränsen (den senaste raden före den) så att en pågående tjänst inte tappas
    while (this.events.length > 1 && this.events[1].t < cutoff) this.events.shift();
    if (this.events.length > MAX_EVENTS) this.events = this.events.slice(-MAX_EVENTS);
    this.flush();
  }

  flush() {
    if (!this.file) return;
    try {
      const tmp = this.file + '.' + process.pid + '.tmp';
      fs.writeFileSync(tmp, this.events.map((e) => JSON.stringify(e)).join('\n') + '\n', { mode: 0o644 });
      fs.renameSync(tmp, this.file);
    } catch (e) { /* statistiken får aldrig störa kiosken */ }
  }
}

module.exports = { UsageLog };
