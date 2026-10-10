'use strict';
// Inställningar för kioskskalet: läser .config, tolkar APPS och bygger listan över tillåtna värdar.
// Ren logik utan Electron, så att den går att testa med node --test (tools/kiosk-test/).
const fs = require('fs');
const { ICONS } = require('./icons');

// Samma regler som load_config i config_lib.sh: bara rader NYCKEL=värde, ett lager citattecken
// tas bort, och inget i filen körs.
function parseEnv(text) {
  const env = {};
  for (let line of String(text || '').split('\n')) {
    line = line.replace(/\r$/, '');
    if (!line || line.startsWith('#') || !line.includes('=')) continue;
    const i = line.indexOf('=');
    const key = line.slice(0, i);
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(key)) continue;
    let val = line.slice(i + 1);
    if (/^".*"$/.test(val) || /^'.*'$/.test(val)) val = val.slice(1, -1);
    env[key] = val;
  }
  return env;
}

function parseUrl(text) {
  try { return new URL(text); } catch (e) { return null; }
}

/**
 * Tjänstens område: värd och sökvägsprefix. Tomt prefix i APPS betyder adressens värd och sökväg som katalog
 * (/kiosk och /kiosk/ ger /kiosk/, /app/index.html ger /app/).
 */
class Scope {
  constructor(host, prefix) { this.host = host; this.prefix = prefix; }

  static directory(path, explicit) {
    let p = !path ? '/' : path;
    if (!p.endsWith('/')) {
      const last = p.slice(p.lastIndexOf('/') + 1);
      p = !explicit && last.includes('.') ? p.slice(0, p.lastIndexOf('/') + 1) : p + '/';
    }
    return p;
  }

  static parse(value) {
    if (!value || !value.trim()) return null;
    let v = value.trim();
    if (!v.includes('://')) v = 'https://' + v;
    const u = parseUrl(v);
    if (!u || !u.hostname) return null;
    return new Scope(u.hostname.toLowerCase(), Scope.directory(u.pathname, true));
  }

  static fromStartUrl(url) {
    const u = parseUrl(url);
    if (!u || !u.hostname) return null;
    return new Scope(u.hostname.toLowerCase(), Scope.directory(u.pathname, false));
  }

  contains(url) {
    const u = parseUrl(url);
    if (!u || !u.hostname || u.hostname.toLowerCase() !== this.host) return false;
    const path = u.pathname || '/';
    return (path + '/').startsWith(this.prefix) || path.startsWith(this.prefix);
  }
}

/** Högst sex tjänster: på förstasidan sex kort, i appläget hem-appen och fem till */
const MAX_APPS = 6;

class App {
  constructor(o) { Object.assign(this, o); }
  /** Namn och beskrivning på besökarens språk; saknas den engelska används den svenska */
  nameFor(en) { return en && this.labelEn ? this.labelEn : this.label; }
  descFor(en) { return en && this.descEn ? this.descEn : this.desc; }
}

function makeApp(f) {
  const label = (f.label || '').trim();
  const url = (f.url || '').trim();
  const u = parseUrl(url);
  if (!label || !u || u.protocol !== 'https:' || !u.hostname) return null;
  return new App({
    label, url,
    icon: (f.icon || '').trim(),
    scope: Scope.parse(f.scope || '') || Scope.fromStartUrl(url),
    desc: (f.desc || '').trim(),
    labelEn: (f.labelEn || '').trim(),
    descEn: (f.descEn || '').trim(),
  });
}

/**
 * APPS har två former. En JSON-lista (när någon text innehåller | , " eller radbrytning):
 * [{"name":"Sök","url":"https://…","icon":"search","scope":"","desc":"…","nameEn":"…","descEn":"…"}].
 * Annars en post per rad: "Namn|https://adress/|ikon|område|beskrivning|namn_en|beskrivning_en".
 * Allt utom namn och adress är valfritt. Ogiltiga poster hoppas över, och går JSON-listan inte att
 * läsa tolkas texten som rader.
 */
function parseApps(raw) {
  if (!raw || !raw.trim()) return [];
  const text = raw.trim();
  if (text.startsWith('[')) {
    try {
      const list = JSON.parse(text);
      if (Array.isArray(list)) {
        const apps = [];
        for (const o of list) {
          if (!o || typeof o !== 'object') continue;
          const a = makeApp({ label: o.name, url: o.url, icon: o.icon, scope: o.scope, desc: o.desc, labelEn: o.nameEn, descEn: o.descEn });
          if (!a) continue;
          if (apps.length >= MAX_APPS) break;
          apps.push(a);
        }
        return apps;
      }
    } catch (e) { /* tolkas som rader */ }
  }
  // .config kan inte innehålla radbrytningar i ett värde, så en bokstavlig \n räknas också som radslut
  const lines = text.includes('\n') ? text.split(/\r?\n/) : (text.includes('\\n') ? text.split('\\n') : text.split(','));
  const apps = [];
  for (const line of lines) {
    if (!line.trim()) continue;
    const p = line.split('|').map((s) => s.trim());
    const a = makeApp({ label: p[0], url: p[1], icon: p[2], scope: p[3], desc: p[4], labelEn: p[5], descEn: p[6] });
    if (!a) continue;
    if (apps.length >= MAX_APPS) break;
    apps.push(a);
  }
  return apps;
}

/** Ett informationsfält: "Etikett|typ|värde|Label". Typ text, url (https) eller clock. Ogiltig rad ger null. */
class Field {
  constructor(label, labelEn, type, value) { Object.assign(this, { label, labelEn, type, value }); }
  labelFor(en) { return en && this.labelEn ? this.labelEn : this.label; }

  static parse(line) {
    if (!line || !line.trim()) return null;
    const p = line.split('|').map((s) => s.trim());
    const type = (p[1] || '').toLowerCase();
    const label = p[0] || '', value = p[2] || '', labelEn = p[3] || '';
    if (type === 'clock') return new Field(label, labelEn, type, '');
    if (type === 'text' && value) return new Field(label, labelEn, type, value);
    if (type === 'url' && value.startsWith('https://') && parseUrl(value)) return new Field(label, labelEn, type, value);
    return null;
  }
}

const MAX_FIELDS = 4;

function csv(value) {
  return String(value || '').split(/[,\s]+/).map((s) => s.trim()).filter(Boolean);
}

function bool(value, def) {
  if (value === undefined || value === '') return def;
  return String(value).toLowerCase() === 'true';
}

function intOr(value, def) {
  const n = parseInt(value, 10);
  return Number.isFinite(n) && n >= 0 ? n : def;
}

/** Bygger skalets inställningar från en tolkad .config och värdlistan som allowlist_from_ezproxy.sh skriver */
function buildSettings(env, hostsText) {
  let apps = parseApps(env.APPS);
  // Utan APPS: startsidorna (WEBSITES) som tjänster, så att en dator utan nya inställningar ändå fungerar
  if (!apps.length) {
    apps = csv(env.WEBSITES).slice(0, MAX_APPS).map((url) => {
      const u = parseUrl(url);
      return u ? makeApp({ label: u.hostname.replace(/^www\./, ''), url }) : null;
    }).filter(Boolean);
  }
  const homeMode = env.HOME_MODE === 'app' ? 'app' : 'launcher';
  const scale = parseInt(env.INITIAL_SCALE, 10);
  const sessionMin = intOr(env.SESSION_IDLE, 0);
  return {
    apps,
    homeMode,
    language: env.LANGUAGE === 'en' ? 'en' : 'sv',
    navigation: bool(env.NAVIGATION, true),
    startLabel: (env.START_LABEL || '').trim(),
    startIcon: (env.START_ICON || '').trim() || 'house',
    texts: {
      title: env.LAUNCHER_TITLE || '', titleEn: env.LAUNCHER_TITLE_EN || '',
      subtitle: env.LAUNCHER_SUBTITLE || '', subtitleEn: env.LAUNCHER_SUBTITLE_EN || '',
      footer: env.LAUNCHER_FOOTER || '', footerEn: env.LAUNCHER_FOOTER_EN || '',
    },
    fields: [env.LAUNCHER_FIELD_1, env.LAUNCHER_FIELD_2, env.LAUNCHER_FIELD_3, env.LAUNCHER_FIELD_4]
      .map((line) => Field.parse(line)).filter(Boolean).slice(0, MAX_FIELDS),
    message: {
      text: (env.LAUNCHER_MESSAGE || '').trim(), textEn: (env.LAUNCHER_MESSAGE_EN || '').trim(),
      url: (env.LAUNCHER_MESSAGE_URL || '').trim(),
      style: ['info', 'warning', 'alert'].includes(env.LAUNCHER_MESSAGE_STYLE) ? env.LAUNCHER_MESSAGE_STYLE : 'warning',
      // Ikonen före texten: none = ingen, annars en av ikonerna (standard info). Okänt namn ger info.
      icon: (env.LAUNCHER_MESSAGE_ICON || '').trim().toLowerCase() === 'none' ? ''
        : (ICONS[(env.LAUNCHER_MESSAGE_ICON || '').trim().toLowerCase()] ? (env.LAUNCHER_MESSAGE_ICON || '').trim().toLowerCase() : 'info'),
    },
    // Zoom på tjänsternas sidor, i procent (10–500, standard 100). Skalets egna sidor påverkas inte.
    initialScale: Number.isFinite(scale) ? Math.max(10, Math.min(500, scale)) : 100,
    refreshMin: Math.max(1, Math.min(60, intOr(env.LAUNCHER_REFRESH, 1))),
    sessionSec: sessionMin * 60,
    warnSec: intOr(env.IDLE_WARNING, 60),
    printing: bool(env.PRINTER, false),
    downloads: bool(env.DOWNLOADS, false), // som sökdatorer: blockerat om inget annat sägs
    allowedHosts: csv(env.WHITE_LIST).concat(String(hostsText || '').split('\n').map((s) => s.trim()).filter((s) => s && !s.startsWith('#'))),
  };
}

function loadSettings(configPath, hostsPath) {
  let env = {};
  let hosts = '';
  try { env = parseEnv(fs.readFileSync(configPath, 'utf8')); } catch (e) { console.error('Kunde inte läsa', configPath, e.message); }
  try { hosts = fs.readFileSync(hostsPath, 'utf8'); } catch (e) { /* värdlistan är valfri */ }
  return buildSettings(env, hosts);
}

module.exports = { parseEnv, parseApps, buildSettings, loadSettings, Scope, Field, MAX_APPS, MAX_FIELDS };
