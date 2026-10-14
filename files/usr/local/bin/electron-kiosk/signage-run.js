'use strict';
// Skylt (COMPUTER_TYPE=signage med SIGN_SHELL=true): sidorna i SIGN_PAGES visas i tur och ordning i helskärm, utan någon
// inmatning. En sida som inte går att ladda visas som felsida (utan knappar) och laddas om av sig själv; rotationen går vidare.
// Sidorna ritas för skärmens verkliga storlek (INITIAL_SCALE gäller), inte för 1280/800 som kioskens egna sidor.
const path = require('path');
const { BrowserWindow, WebContentsView, Menu, ipcMain, net } = require('electron');
const { SandboxedPage } = require('./sandboxed-page');
const { bothStrings } = require('./strings');
const { nextIndex } = require('./signage');

const RETRY_MS = 30 * 1000;
const PRELOAD_S = 10;       // nästa sida börjar laddas så här många sekunder före bytet (kortare om sidan visas kortare tid)
const SETTLE_MS = 1500;     // tid efter att sidan laddats för att dess skript ska hinna rita klart
const MAX_WAIT_MS = 10000;  // väntar högst så här länge på en sida som inte är färdig vid bytet

module.exports = function startSignage({ settings, policy, windowed }) {
  Menu.setApplicationMenu(null);
  const win = new BrowserWindow({
    kiosk: !windowed, width: 1280, height: 720, backgroundColor: '#000000',
    webPreferences: { sandbox: true, contextIsolation: true, devTools: false },
  });
  win.removeMenu();

  const sign = settings.signage;
  let index = 0;
  let rotateTimer = null;
  let retryTimer = null;
  let overlay = null; // { type: 'error', offline } eller null

  // Två vyer: den ena visas medan nästa sida laddas och ritas färdigt bakom den, så bytet sker utan väntan.
  // Båda är synliga (inte dolda, då stryps skripten) och ligger över varandra; den aktiva ligger överst.
  const mk = (name) => new SandboxedPage({
    name, policy, js: sign.js, touch: false, noScroll: true, allowRedirects: true,
    onChange: () => settle(),
  });
  const views = [mk('sign-a'), mk('sign-b')];
  let active = 0;
  const page = { get current() { return views[active]; } };
  for (const v of views) win.contentView.addChildView(v.view);
  win.contentView.addChildView(views[active].view); // den aktiva överst

  const overlayView = new WebContentsView({ webPreferences: {
    sandbox: true, contextIsolation: true, nodeIntegration: false, devTools: false,
    preload: path.join(__dirname, 'ui-preload.js'),
  } });
  overlayView.setBackgroundColor('#00000000');
  win.contentView.addChildView(overlayView);
  overlayView.webContents.loadFile(path.join(__dirname, 'overlay.html'));
  overlayView.webContents.on('did-finish-load', () => layout());

  ipcMain.handle('ui:state', (e) => {
    if (e.sender !== overlayView.webContents) return null;
    return state();
  });

  function state() {
    return { signage: true, lang: 'sv', overlay, bi: bothStrings(0), startBi: { sv: '', en: '' }, canBack: false, apps: [], strings: bothStrings(0).sv };
  }
  function push() { if (!overlayView.webContents.isDestroyed()) overlayView.webContents.send('ui:state', state()); }

  function layout() {
    const [w, h] = win.getContentSize();
    for (const v of views) {
      v.view.setBounds({ x: 0, y: 0, width: w, height: h });
      v.setZoom(settings.initialScale / 100);
    }
    overlayView.setVisible(!!overlay);
    overlayView.setBounds({ x: 0, y: 0, width: w, height: h });
    // Skalets egna sidor är ritade för 1280 (liggande) eller 800 (stående) pixlar och skalas efter bredden
    overlayView.webContents.setZoomFactor(Math.min(2.5, Math.max(0.6, w / (h > w ? 800 : 1280))));
  }

  /** Visar felsidan så länge den aktuella sidan inte har kunnat laddas, och försöker igen */
  function settle() {
    const cur = page.current;
    const failed = cur.failed && !cur.ok;
    overlay = failed ? { type: 'error', offline: !net.isOnline() } : null;
    layout(); push();
    clearTimeout(retryTimer);
    if (failed) retryTimer = setTimeout(() => page.current.load(sign.pages[index].url), RETRY_MS);
  }

  /** Lägger den aktiva vyn överst, med felsidan ovanför */
  function raise() {
    win.contentView.addChildView(views[active].view);
    win.contentView.addChildView(overlayView);
  }

  /** Byter till den förladdade vyn när nästa sida är klar (eller efter MAX_WAIT_MS) */
  function swapTo(next, waited) {
    const standby = views[1 - active];
    const ready = standby.ok && Date.now() - standby.okAt >= SETTLE_MS; // laddad och skripten har haft tid att rita
    if (!ready && !standby.failed && waited < MAX_WAIT_MS) { rotateTimer = setTimeout(() => swapTo(next, waited + 500), 500); return; }
    const old = views[active];
    active = 1 - active;
    index = next;
    raise();
    settle();
    setTimeout(() => { if (views[active] !== old) old.unload(); }, 1000); // den gamla vyn släpps (stoppar skript och film)
    scheduleNext();
  }

  /** Planerar förladdning och byte för sidan som visas nu */
  function scheduleNext() {
    clearTimeout(rotateTimer);
    if (sign.pages.length < 2) return;
    const p = sign.pages[index];
    const next = nextIndex(index, sign.pages.length);
    const lead = Math.min(PRELOAD_S, Math.max(1, p.seconds - 2));
    rotateTimer = setTimeout(() => {
      views[1 - active].load(sign.pages[next].url);
      rotateTimer = setTimeout(() => swapTo(next, 0), lead * 1000);
    }, (p.seconds - lead) * 1000);
  }

  function show(i) {
    index = i;
    views[active].load(sign.pages[i].url);
    scheduleNext();
  }

  win.on('resize', layout);
  if (!sign.pages.length) {
    // Inget att visa: felsidan (utan knappar) står kvar tills inställningarna ändrats
    overlay = { type: 'error', offline: false };
    layout(); overlayView.webContents.on('did-finish-load', push);
    return;
  }
  show(0);
  // En enda sida laddas om med SESSION_IDLE minuters mellanrum (som den gamla skylten)
  if (sign.pages.length === 1 && sign.reloadMin > 0) setInterval(() => page.current.load(sign.pages[0].url), sign.reloadMin * 60 * 1000);
};
