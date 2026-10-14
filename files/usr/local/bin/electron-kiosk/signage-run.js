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

  const page = new SandboxedPage({
    name: 'sign', policy, js: sign.js, touch: false, noScroll: true, allowRedirects: true,
    onChange: () => settle(),
  });
  win.contentView.addChildView(page.view);

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
    page.view.setBounds({ x: 0, y: 0, width: w, height: h });
    page.setZoom(settings.initialScale / 100);
    overlayView.setVisible(!!overlay);
    overlayView.setBounds({ x: 0, y: 0, width: w, height: h });
    // Skalets egna sidor är ritade för 1280 (liggande) eller 800 (stående) pixlar och skalas efter bredden
    overlayView.webContents.setZoomFactor(Math.min(2.5, Math.max(0.6, w / (h > w ? 800 : 1280))));
  }

  /** Visar felsidan så länge den aktuella sidan inte har kunnat laddas, och försöker igen */
  function settle() {
    const failed = page.failed && !page.ok;
    overlay = failed ? { type: 'error', offline: !net.isOnline() } : null;
    layout(); push();
    clearTimeout(retryTimer);
    if (failed) retryTimer = setTimeout(() => page.load(sign.pages[index].url), RETRY_MS);
  }

  function show(i) {
    index = i;
    clearTimeout(rotateTimer);
    const p = sign.pages[index];
    page.load(p.url);
    if (sign.pages.length > 1) rotateTimer = setTimeout(() => show(nextIndex(index, sign.pages.length)), p.seconds * 1000);
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
  if (sign.pages.length === 1 && sign.reloadMin > 0) setInterval(() => page.load(sign.pages[0].url), sign.reloadMin * 60 * 1000);
};
