'use strict';
// Vilka sidor skalet får visa: bara https, och bara värdar från APPS, WHITE_LIST och värdlistan
// (allowed-hosts.txt, som innehåller WHITE_LIST). Underdomäner ingår: kth.se tillåter www.kth.se. Allt annat (andra värdar, file:, data:,
// javascript:, intent: …) blockeras. Chromium-policyerna gäller inte Electron, därför görs det här.

function hostOf(url) {
  try { const h = new URL(String(url).trim()).hostname; return h ? h.toLowerCase() : null; } catch (e) { return null; }
}

/** "https://www.kth.se/x" och "www.kth.se" blir "www.kth.se"; "*.kth.se" blir "kth.se"; ogiltigt blir null */
function normalize(entry) {
  if (!entry) return null;
  let e = String(entry).trim().toLowerCase();
  if (!e) return null;
  if (e.includes('://')) e = hostOf(e);
  if (!e) return null;
  if (e.startsWith('*.')) e = e.slice(2);
  e = e.split('/')[0].split(':')[0];
  return /^[a-z0-9.-]+\.[a-z]{2,}$/.test(e) ? e : null;
}

class UrlPolicy {
  /** apps: tjänsterna (deras värdar tillåts), extraHosts: övriga värdnamn eller adresser */
  constructor(apps, extraHosts) {
    this.hosts = [];
    for (const a of apps || []) this.add(hostOf(a.url));
    for (const h of extraHosts || []) this.add(normalize(h));
  }

  add(host) {
    const n = normalize(host);
    if (n && !this.hosts.includes(n)) this.hosts.push(n);
  }

  allows(url) {
    let u;
    try { u = new URL(String(url)); } catch (e) { return false; }
    if (u.protocol !== 'https:' || !u.hostname) return false;
    const host = u.hostname.toLowerCase();
    return this.hosts.some((h) => host === h || host.endsWith('.' + h));
  }

  /** En http-länk till en tillåten webbplats som https-adress, annars null (sidan hämtas då krypterat) */
  httpsUpgrade(url) {
    let u;
    try { u = new URL(String(url)); } catch (e) { return null; }
    if (u.protocol !== 'http:') return null;
    u.protocol = 'https:';
    return this.allows(u.href) ? u.href : null;
  }
}

module.exports = { UrlPolicy, normalize, hostOf };
