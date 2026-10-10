'use strict';
// Kioskläge (COMPUTER_TYPE=kiosk): helskärm med förstasida, tjänster i en egen sidvy, en navigeringsram
// som sidorna inte kan påverka, överlägg (Är du kvar?, blockerad länk, felsida) och ett skärmtangentbord.
// Körs med Electron från electron-login: electron main.js [--windowed] [--config fil] [--hosts fil]
const { app, BrowserWindow, WebContentsView, Menu, ipcMain, powerMonitor, session, net } = require('electron');
const path = require('path');
const { loadSettings } = require('./config');
const { UrlPolicy, hostOf } = require('./policy');
const { idleState } = require('./idle');
const { InfoFeed } = require('./info');
const { stringsFor, pick } = require('./strings');

const argv = process.argv.slice(2);
const option = (name, def) => { const i = argv.indexOf(name); return i >= 0 && argv[i + 1] ? argv[i + 1] : def; };
const WINDOWED = argv.includes('--windowed');
const settings = loadSettings(
  option('--config', '/usr/local/bin/config/.config'),
  option('--hosts', '/var/lib/publicom/allowed-hosts.txt'));
const policy = new UrlPolicy(settings.apps, settings.allowedHosts);
const info = new InfoFeed(settings, policy);

const DESIGN_W = { landscape: 1280, portrait: 800 };    // skalets sidor är ritade för 1280 px (liggande) och 800 px (stående) och skalas med bredden, som i PubLiKiosk
const BAR_H = 88;                                       // navigeringsramen, i designpixlar
const KB_H = { text: 392, email: 464, number: 392 };    // skärmtangentbordet, i designpixlar
const PAGE_PARTITION = 'kiosk-page';                    // utan persist: allt ligger i minnet

app.commandLine.appendSwitch('overscroll-history-navigation', '0'); // ingen svep-bakåt på pekskärmen
if (!app.requestSingleInstanceLock()) app.quit();

let win, pageView, homeView, barView, kbView, overlayView;
let autoRetry = null;
let lastFailedUrl = null;
const S = {
  lang: settings.language,
  view: settings.homeMode === 'app' ? 'app' : 'home',
  current: settings.homeMode === 'app' ? 0 : -1,
  overlay: null,
  canBack: false,
  kbOpen: false, kbType: 'text', kbEnter: 'enter', suppressUntil: 0,
};

const ui = (file) => path.join(__dirname, file);
const uiViews = () => [homeView, barView, overlayView].filter(Boolean);
const zoom = (w, h) => Math.min(2.5, Math.max(0.6, w / (h > w ? DESIGN_W.portrait : DESIGN_W.landscape)));

// ---------- tillstånd till skalets egna sidor ----------

function uiState() {
  const en = S.lang === 'en';
  const t = stringsFor(S.lang, S.overlay && S.overlay.secondsLeft);
  const cur = settings.apps[S.current];
  return {
    lang: S.lang,
    strings: t,
    mode: S.view,
    homeMode: settings.homeMode,
    navigation: settings.navigation,
    apps: settings.apps.map((a) => ({ name: a.nameFor(en), desc: a.descFor(en), icon: a.icon || 'info' })),
    title: pick(S.lang, settings.texts.title, settings.texts.titleEn, t.title),
    subtitle: pick(S.lang, settings.texts.subtitle, settings.texts.subtitleEn, t.subtitle),
    footer: pick(S.lang, settings.texts.footer, settings.texts.footerEn, ''),
    info: info.view(en),
    startLabel: en ? t.start : (settings.startLabel || t.start),
    startIcon: settings.startIcon,
    canBack: S.canBack,
    currentIndex: S.current,
    current: cur ? { name: cur.nameFor(en), icon: cur.icon || 'info', host: hostOf(cur.url) } : null,
    overlay: S.overlay,
  };
}

function pushState() {
  const s = uiState();
  for (const v of uiViews()) if (!v.webContents.isDestroyed()) v.webContents.send('ui:state', s);
}

// ---------- placering av vyerna ----------

function layout() {
  if (!win) return;
  const [w, h] = win.getContentSize();
  const z = zoom(w, h);
  const inApp = S.view === 'app';
  const showBar = inApp && settings.navigation && !S.kbOpen;
  const barH = showBar ? Math.round(BAR_H * z) : 0;
  const kbH = S.kbOpen && inApp ? Math.round(KB_H[S.kbType] * z) : 0;
  const full = { x: 0, y: 0, width: w, height: h };

  homeView.setVisible(!inApp);
  homeView.setBounds(full);
  if (pageView) {
    pageView.setVisible(inApp);
    pageView.setBounds({ x: 0, y: 0, width: w, height: Math.max(0, h - barH - kbH) });
  }
  barView.setVisible(showBar);
  barView.setBounds({ x: 0, y: h - Math.round(BAR_H * z), width: w, height: Math.round(BAR_H * z) });
  kbView.setVisible(S.kbOpen && inApp);
  kbView.setBounds({ x: 0, y: h - kbH, width: w, height: kbH });
  overlayView.setVisible(!!S.overlay);
  overlayView.setBounds(full);
  for (const v of [homeView, barView, kbView, overlayView]) v.webContents.setZoomFactor(z);
}

function update() { layout(); pushState(); }

// ---------- överlägg ----------

function showOverlay(o) {
  S.overlay = o;
  S.kbOpen = false;
  update();
}

function hideOverlay() {
  if (!S.overlay) return;
  S.overlay = null;
  if (autoRetry) { clearInterval(autoRetry); autoRetry = null; }
  update();
}

function showBlocked(url) {
  const host = hostOf(url);
  showOverlay({ type: 'blocked', url: String(url), host, qr: /^https?:/i.test(String(url)) });
}

function showError(url) {
  lastFailedUrl = url;
  const offline = !net.isOnline();
  showOverlay({ type: 'error', offline });
  if (offline && !autoRetry) {
    // Laddar om av sig självt så snart nätverket är tillbaka
    autoRetry = setInterval(() => {
      if (net.isOnline() && pageView) { hideOverlay(); pageView.webContents.loadURL(lastFailedUrl); }
    }, 4000);
  }
}

// ---------- sidvyn ----------

function guard(e, url) {
  if (url === 'about:blank' || policy.allows(url)) return;
  e.preventDefault();
  const up = policy.httpsUpgrade(url);
  if (up) pageView.webContents.loadURL(up); else showBlocked(url);
}

function openUrl(url) { // länkar som vill öppna ett nytt fönster öppnas i samma vy
  const up = policy.allows(url) ? url : policy.httpsUpgrade(url);
  if (up) pageView.webContents.loadURL(up); else showBlocked(url);
}

function createPage() {
  if (pageView) {
    win.contentView.removeChildView(pageView);
    if (!pageView.webContents.isDestroyed()) pageView.webContents.close();
  }
  pageView = new WebContentsView({ webPreferences: {
    sandbox: true, contextIsolation: true, nodeIntegration: false, devTools: false,
    nodeIntegrationInSubFrames: true, // fält i iframes ska också rapporteras till tangentbordet
    partition: PAGE_PARTITION,
    preload: ui('page-preload.js'),
  } });
  win.contentView.addChildView(pageView, 0); // underst, så att navigering, tangentbord och överlägg ligger över
  const wc = pageView.webContents;
  wc.setVisualZoomLevelLimits(1, 1);          // ingen nypzoom
  // INITIAL_SCALE gäller sidvyn, utöver skalningen av skalets egna sidor. Chromium minns zoom per värd och
  // sidan får ny sidmiljö vid varje navigering, så faktorn sätts om efter varje laddning.
  const applyScale = () => { if (!wc.isDestroyed()) wc.setZoomFactor(settings.initialScale / 100); };
  wc.on('dom-ready', applyScale);
  wc.on('did-navigate', applyScale);
  wc.on('did-finish-load', applyScale);
  wc.setWindowOpenHandler(({ url }) => { openUrl(url); return { action: 'deny' }; });
  wc.on('will-navigate', (e, url) => guard(e, url || e.url));
  wc.on('will-redirect', (e, url) => guard(e, url || e.url));
  const nav = () => { S.canBack = !wc.isDestroyed() && wc.navigationHistory.canGoBack(); pushState(); };
  wc.on('did-navigate', nav);
  wc.on('did-navigate-in-page', nav);
  wc.on('did-fail-load', (_e, code, _desc, url, isMain) => { if (isMain && code !== -3) showError(url); });
  wc.on('render-process-gone', () => goHome());
  wc.on('before-input-event', (e, input) => {
    if (input.type === 'keyDown' && input.control && !settings.printing && input.key.toLowerCase() === 'p') e.preventDefault();
  });
  S.canBack = false;
}

function resetSessionData() {
  const ses = session.fromPartition(PAGE_PARTITION);
  ses.clearStorageData().catch(() => {});
  ses.clearCache().catch(() => {});
  ses.clearAuthCache().catch(() => {});
}

function openApp(i) {
  const a = settings.apps[i];
  if (!a) return;
  if (!pageView) createPage();
  hideOverlay();
  S.view = 'app';
  S.current = i;
  S.kbOpen = false;
  pageView.webContents.loadURL(a.url);
  update();
}

/** Startsida: allt som besökaren gjort rensas (cookies, cache, historik), språket återställs */
function goHome() {
  if (autoRetry) { clearInterval(autoRetry); autoRetry = null; }
  S.overlay = null;
  S.kbOpen = false;
  S.lang = settings.language;
  resetSessionData();
  createPage();
  if (settings.homeMode === 'app') { openApp(0); return; }
  S.view = 'home';
  S.current = -1;
  update();
  refreshInfo();
}

// ---------- tangentbord ----------

function showKeyboard(m) {
  if (S.view !== 'app' || S.overlay) return;
  const type = KB_H[m && m.type] ? m.type : 'text';
  const enter = (m && m.enter) || 'enter';
  const changed = !S.kbOpen || type !== S.kbType || enter !== S.kbEnter;
  S.kbOpen = true; S.kbType = type; S.kbEnter = enter;
  layout();
  if (changed) kbView.webContents.send('layout', { type, enter });
  // Håll fältet synligt ovanför tangentbordet
  pageView.webContents.executeJavaScript(
    'document.activeElement && document.activeElement.scrollIntoView && document.activeElement.scrollIntoView({block:"center"})'
  ).catch(() => {});
}

function hideKeyboard() {
  if (!S.kbOpen) return;
  S.suppressUntil = Date.now() + 800; // efter nedfällning visas det bara av ett riktigt tryck i ett fält
  S.kbOpen = false;
  update();
}

function sendKey(msg) {
  if (!pageView) return;
  const wc = pageView.webContents;
  wc.focus(); // tangentbordsvyn fick fokus vid tryckningen; ge tillbaka det till sidan
  if (msg.kind === 'text' && typeof msg.text === 'string') {
    wc.insertText(msg.text);
  } else if (msg.kind === 'back') {
    wc.sendInputEvent({ type: 'keyDown', keyCode: 'Backspace' });
    wc.sendInputEvent({ type: 'keyUp', keyCode: 'Backspace' });
  } else if (msg.kind === 'enter') {
    wc.sendInputEvent({ type: 'keyDown', keyCode: 'Enter' });
    wc.sendInputEvent({ type: 'char', keyCode: '\r' });
    wc.sendInputEvent({ type: 'keyUp', keyCode: 'Enter' });
    // Sök, Gå, Skicka och Klar avslutar inmatningen: fäll ner, som på en telefon. Retur och Nästa lämnar det uppe.
    if (['search', 'go', 'send', 'done'].includes(S.kbEnter)) setTimeout(hideKeyboard, 150);
  } else if (msg.kind === 'hide') {
    hideKeyboard();
  }
}

// ---------- förstasidans nederkant ----------

// Text från webbadresser hämtas bara medan förstasidan visas
function refreshInfo() {
  if (S.view !== 'home' || !info.urls().length) return;
  info.refresh().then(pushState).catch(() => {});
}

// ---------- inaktivitet ----------

function idleTick() {
  if (!win || settings.sessionSec <= 0) return;
  const idle = powerMonitor.getSystemIdleTime();
  if (S.view !== 'app') {
    if (idle >= settings.sessionSec && S.lang !== settings.language) { S.lang = settings.language; pushState(); } // förstasidan återställs tyst
    return;
  }
  const r = idleState(idle, settings.sessionSec, settings.warnSec);
  if (r.state === 'expired') goHome();
  else if (r.state === 'warning') {
    // Nedräkningen (ringen) tömmas från antalet sekunder när varningen först visas
    const total = S.overlay && S.overlay.type === 'idle' ? S.overlay.total : r.secondsLeft;
    showOverlay({ type: 'idle', secondsLeft: r.secondsLeft, total });
  }
  else if (S.overlay && S.overlay.type === 'idle') hideOverlay();
}

// ---------- start ----------

app.whenReady().then(() => {
  Menu.setApplicationMenu(null);
  win = new BrowserWindow({
    kiosk: !WINDOWED, width: 1280, height: 800, backgroundColor: '#000061',
    webPreferences: { sandbox: true, contextIsolation: true, devTools: false },
  });
  win.removeMenu();

  const makeUi = (file, extra) => {
    const v = new WebContentsView({ webPreferences: Object.assign({
      sandbox: true, contextIsolation: true, nodeIntegration: false, devTools: false,
      preload: ui('ui-preload.js'),
    }, extra) });
    win.contentView.addChildView(v);
    v.webContents.loadFile(ui(file));
    v.webContents.on('did-finish-load', layout);
    return v;
  };
  homeView = makeUi('launcher.html');
  barView = makeUi('bar.html');
  kbView = new WebContentsView({ webPreferences: {
    sandbox: true, contextIsolation: true, nodeIntegration: false, devTools: false, preload: ui('kb-preload.js'),
  } });
  win.contentView.addChildView(kbView);
  kbView.webContents.loadFile(ui('keyboard.html'));
  overlayView = makeUi('overlay.html');
  overlayView.setBackgroundColor('#00000000');

  // Sidvyn får inga behörigheter (kamera, plats, notiser …) och inga nedladdningar om inte DOWNLOADS=true
  const ses = session.fromPartition(PAGE_PARTITION);
  ses.setPermissionRequestHandler((_wc, _perm, cb) => cb(false));
  ses.setPermissionCheckHandler(() => false);
  ses.on('will-download', (e, item) => { if (!settings.downloads) item.cancel(); });

  // Meddelanden accepteras bara från rätt vy
  const isUi = (e) => uiViews().some((v) => v.webContents === e.sender);
  const isPage = (e) => pageView && e.sender === pageView.webContents;
  ipcMain.handle('ui:state', (e) => (isUi(e) ? uiState() : null));
  ipcMain.on('page:cfg', (e) => { e.returnValue = isPage(e) ? { printing: settings.printing } : { printing: false }; });
  ipcMain.on('ui:act', (e, name, arg) => {
    if (!isUi(e)) return;
    if (name === 'openApp' && Number.isInteger(arg)) openApp(arg);
    else if (name === 'setLang' && (arg === 'sv' || arg === 'en')) { S.lang = arg; pushState(); }
    else if (name === 'home') goHome();
    else if (name === 'back') { if (pageView && pageView.webContents.navigationHistory.canGoBack()) pageView.webContents.navigationHistory.goBack(); else goHome(); }
    else if (name === 'overlayClose' || name === 'idleContinue') hideOverlay();
    else if (name === 'retry') { hideOverlay(); if (lastFailedUrl) pageView.webContents.loadURL(lastFailedUrl); }
  });
  ipcMain.on('field-focus', (e, m) => {
    if (!isPage(e) || !m) return;
    if (!m.tap && Date.now() < S.suppressUntil) return;
    showKeyboard(m);
  });
  ipcMain.on('field-away', (e) => { if (isPage(e)) hideKeyboard(); });
  ipcMain.on('field-auto', () => {}); // fokus som sidan satte själv visar inte tangentbordet
  ipcMain.on('kb', (e, m) => { if (e.sender === kbView.webContents && m) sendKey(m); });

  win.on('resize', layout);
  goHome();
  setInterval(idleTick, 1000);
  setInterval(refreshInfo, settings.refreshMin * 60 * 1000);
});

app.on('window-all-closed', () => app.quit());
