'use strict';
// En egen vy som bara visar en webbsida (fotrad som webbsida, attract loop). Inget nås från sidan:
// ingen brygga mot skalet, ingen navigering (länkar, omdirigeringar och nya fönster nekas), ingen delad session,
// inga behörigheter, inga nedladdningar, ingen nypzoom. Sidan och dess delresurser (bilder, film, typsnitt, skript)
// hämtas bara från tillåtna värdar (https). JavaScript är av om inte js är satt, och tryck nekas om inte touch är satt.
// Film utan ljud autospelar, film med ljud gör det inte (autoplayPolicy user-gesture-required).
const { WebContentsView, session } = require('electron');

const NO_POINTER = 'html, body, * { pointer-events: none !important; }';

class SandboxedPage {
  /** opts: name (partitionens namn), policy (UrlPolicy), js, touch, onChange (anropas när ok ändras) */
  constructor(opts) {
    this.name = opts.name;
    this.policy = opts.policy;
    this.touch = !!opts.touch;
    this.onChange = opts.onChange || (() => {});
    this.url = '';
    this.ok = false;
    this.zoom = 1;
    this.status = 0;
    this.failed = false;
    const partition = 'kiosk-' + this.name; // utan persist: allt ligger i minnet
    this.view = new WebContentsView({ webPreferences: {
      sandbox: true, contextIsolation: true, nodeIntegration: false, devTools: false, webSecurity: true,
      javascript: !!opts.js, partition, autoplayPolicy: 'user-gesture-required', spellcheck: false,
    } });
    const ses = session.fromPartition(partition);
    ses.setPermissionRequestHandler((_wc, _perm, cb) => cb(false));
    ses.setPermissionCheckHandler(() => false);
    ses.on('will-download', (e, item) => item.cancel());
    ses.webRequest.onBeforeRequest((details, cb) => cb({ cancel: !this.allowsRequest(details.url) }));

    const wc = this.view.webContents;
    wc.setWindowOpenHandler(() => ({ action: 'deny' }));
    wc.on('will-navigate', (e) => e.preventDefault());
    wc.on('will-redirect', (e) => e.preventDefault());
    wc.on('will-frame-navigate', (e) => { if (e.isMainFrame) e.preventDefault(); });
    wc.on('before-input-event', (e) => e.preventDefault());
    wc.setVisualZoomLevelLimits(1, 1);
    const apply = () => {
      if (wc.isDestroyed()) return;
      wc.setZoomFactor(this.zoom);
      if (!this.touch) wc.insertCSS(NO_POINTER).catch(() => {});
    };
    wc.on('dom-ready', apply);
    wc.on('did-navigate', (_e, _url, code) => { this.status = code || 0; apply(); });
    wc.on('did-fail-load', (_e, code, _d, _u, isMain) => { if (isMain && code !== -3) this.set(false, true); });
    wc.on('did-finish-load', () => {
      apply();
      this.set(!this.failed && this.url !== '' && wc.getURL() !== 'about:blank' && !(this.status >= 400), this.failed);
    });
  }

  /** https mot tillåtna värdar; data: och blob: (sidans egna) är tillåtna, allt annat nekas */
  allowsRequest(url) {
    const u = String(url);
    if (u.startsWith('data:') || u.startsWith('blob:')) return true;
    return this.policy.allows(u);
  }

  set(ok, failed) {
    const changed = ok !== this.ok;
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
    if (!this.url || !this.policy.allows(this.url)) { this.set(false, true); return; }
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
