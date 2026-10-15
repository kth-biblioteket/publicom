'use strict';
// En egen vy som bara visar en webbsida (fotrad som webbsida, attract loop). Inget nås från sidan:
// ingen brygga mot skalet, ingen navigering (länkar, omdirigeringar och nya fönster nekas), ingen delad session,
// inga behörigheter, inga nedladdningar, ingen nypzoom. Sidan och dess delresurser (bilder, film, typsnitt, skript)
// hämtas bara från tillåtna värdar (https). JavaScript är av om inte js är satt, och tryck nekas om inte touch är satt.
// Film utan ljud autospelar, film med ljud gör det inte (autoplayPolicy user-gesture-required).
const { WebContentsView, session } = require('electron');
const { requestAllowed } = require('./policy');

// Laddningsfel som beror på nätverket (inte på sidan): namnet kan inte slås upp, ingen anslutning, nätverket byttes, adressen nås inte, tidsgräns
const NET_ERRORS = new Set([-105, -106, -21, -109, -118, -7, -100, -101, -102, -104, -112]);

const NO_POINTER = 'html, body, * { pointer-events: none !important; }';

class SandboxedPage {
  /** opts: name (partitionens namn), policy (UrlPolicy), js, touch, onChange (anropas när ok ändras),
   *  allowRedirects: omdirigeringar till tillåtna värdar följs (skylten), annars nekas alla,
   *  anyHttps: delresurser får hämtas från vilken https-adress som helst (SIGN_RESOURCES=all på skylten) */
  constructor(opts) {
    this.name = opts.name;
    this.policy = opts.policy;
    this.touch = !!opts.touch;
    this.allowRedirects = !!opts.allowRedirects;
    this.noScroll = !!opts.noScroll;
    this.anyHttps = !!opts.anyHttps;
    this.onChange = opts.onChange || (() => {});
    this.url = '';
    this.ok = false;
    this.zoom = 1;
    this.status = 0;
    this.failed = false;
    this.netError = false; // senaste misslyckandet berodde på nätverket (DNS, ingen anslutning)
    const partition = 'kiosk-' + this.name; // utan persist: allt ligger i minnet
    this.view = new WebContentsView({ webPreferences: {
      sandbox: true, contextIsolation: true, nodeIntegration: false, devTools: false, webSecurity: true,
      javascript: !!opts.js, partition, autoplayPolicy: 'user-gesture-required', spellcheck: false,
    } });
    const ses = session.fromPartition(partition);
    ses.setPermissionRequestHandler((_wc, _perm, cb) => cb(false));
    ses.setPermissionCheckHandler(() => false);
    ses.on('will-download', (e, item) => item.cancel());
    ses.webRequest.onBeforeRequest((details, cb) => {
      const ok = this.allowsRequest(details.url, details.resourceType);
      if (!ok && process.env.KIOSK_LOG_BLOCKED) console.log('[blockerad]', this.name, details.resourceType, details.url.slice(0, 160));
      cb({ cancel: !ok });
    });

    const wc = this.view.webContents;
    wc.setWindowOpenHandler(() => ({ action: 'deny' }));
    wc.on('will-navigate', (e) => e.preventDefault());
    wc.on('will-redirect', (e, url) => { if (!this.allowRedirects || !this.policy.allows(url || e.url)) e.preventDefault(); });
    wc.on('will-frame-navigate', (e) => { if (e.isMainFrame) e.preventDefault(); });
    wc.on('before-input-event', (e) => e.preventDefault());
    wc.setVisualZoomLevelLimits(1, 1);
    const apply = () => {
      if (wc.isDestroyed()) return;
      wc.setZoomFactor(this.zoom);
      if (!this.touch) wc.insertCSS(NO_POINTER + (this.noScroll ? ' html, body { overflow: hidden !important; }' : '')).catch(() => {});
    };
    wc.on('dom-ready', apply);
    wc.on('did-navigate', (_e, _url, code) => { this.status = code || 0; apply(); });
    wc.on('did-fail-load', (_e, code, desc, failedUrl, isMain) => {
      if (isMain && code !== -3) {
        this.netError = NET_ERRORS.has(code);
        console.log(`[${this.name}] sidan kunde inte laddas: fel ${code} ${desc} ${String(failedUrl).slice(0, 200)}`); this.set(false, true); }
    });
    wc.on('did-finish-load', () => {
      apply();
      const bad = this.status >= 400; // http-svar 400 eller högre räknas som att sidan inte gick att ladda
      if (bad && this.url !== '') console.log(`[${this.name}] sidan svarade http ${this.status}: ${this.url.slice(0, 200)}`);
      this.set(!this.failed && !bad && this.url !== '' && wc.getURL() !== 'about:blank', this.failed || (bad && this.url !== ''));
    });
  }

  /** https mot tillåtna värdar (delresurser från vilken https-adress som helst med anyHttps); data: och blob: är tillåtna, allt annat nekas */
  allowsRequest(url, resourceType) {
    return requestAllowed(this.policy, url, resourceType, this.anyHttps);
  }

  set(ok, failed) {
    const changed = ok !== this.ok || failed !== this.failed;
    if (ok && !this.ok) this.okAt = Date.now();
    this.ok = ok; this.failed = failed;
    if (changed) this.onChange(ok);
  }

  setZoom(z) {
    if (z === this.zoom) return;
    this.zoom = z;
    if (!this.view.webContents.isDestroyed()) this.view.webContents.setZoomFactor(z);
  }

  /** Laddar sidan (på nytt). En adress som inte är https på en tillåten värd laddas inte. */
  load(url) {
    this.url = url || '';
    this.status = 0;
    this.failed = false;
    this.netError = false;
    if (!this.url || !this.policy.allows(this.url)) { console.log(`[${this.name}] adressen tillåts inte eller saknas: ${String(this.url).slice(0, 200)}`); this.set(false, true); return; }
    this.view.webContents.loadURL(this.url).catch(() => { this.set(false, true); });
  }

  /** Släpper sidan (visas inte): laddar en tom sida, så att film och skript stannar */
  unload() {
    this.url = '';
    this.set(false, false);
    if (!this.view.webContents.isDestroyed()) this.view.webContents.loadURL('about:blank').catch(() => {});
    this.view.webContents.setAudioMuted(true);
  }
}

module.exports = { SandboxedPage };
