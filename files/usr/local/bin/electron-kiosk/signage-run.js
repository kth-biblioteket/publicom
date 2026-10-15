'use strict';
// Skylt (COMPUTER_TYPE=signage): sidorna i den spellista som gäller nu (SIGN_SCHEDULE, annars SIGN_PAGES) visas i tur och ordning i helskärm,
// utan någon inmatning. En sida som inte går att ladda visas som felsida (utan knappar) och laddas om av sig själv; rotationen går vidare.
// Sidorna ritas för skärmens verkliga storlek (INITIAL_SCALE gäller), inte för 1280/800 som kioskens egna sidor.
const path = require('path');
const { BrowserWindow, WebContentsView, Menu, ipcMain, net } = require('electron');
const { SandboxedPage } = require('./sandboxed-page');
const { bothStrings } = require('./strings');
const { nextIndex, activeList } = require('./signage');

const RETRY_MS = 30 * 1000;
const SKIP_MS = 10 * 1000;           // en sida som inte gick att ladda lämnas efter så här lång tid i stället för att stå kvar sin hela tid
const SCHEDULE_CHECK_MS = 20 * 1000; // schemat kontrolleras minst varje minut
const PRELOAD_S = 10;       // nästa sida börjar laddas så här många sekunder före bytet (kortare om sidan visas kortare tid)
const SETTLE_MS = 1500;     // tid efter att sidan laddats för att dess skript ska hinna rita klart
const MAX_WAIT_MS = 10000;  // väntar högst så här länge på en sida som inte är färdig vid bytet

module.exports = function startSignage({ settings, policy, windowed }) {
  Menu.setApplicationMenu(null);
  const win = new BrowserWindow({
    kiosk: !windowed, width: 1280, height: 720, backgroundColor: '#000000',
    enableLargerThanScreen: !!process.env.KIOSK_TEST_LARGER, // bara för skärmbilder i full storlek på en mindre skärm
    webPreferences: { sandbox: true, contextIsolation: true, devTools: false },
  });
  win.removeMenu();

  const sign = settings.signage;
  let pages = sign.pages; // spellistan som gäller nu
  let listKey = null;     // vilken lista som visas: schemats namn, '#standard' (SIGN_PAGES) eller '#av' (svart)
  let index = 0;
  let rotateTimer = null;
  let retryTimer = null;
  let skipTimer = null;
  let overlay = null; // { type: 'error', offline } eller null

  // Två vyer: den ena visas medan nästa sida laddas och ritas färdigt bakom den, så bytet sker utan väntan.
  // Båda är synliga (inte dolda, då stryps skripten) och ligger över varandra; den aktiva ligger överst.
  const mk = (name) => new SandboxedPage({
    name, policy, js: sign.js, touch: false, noScroll: true, allowRedirects: true, anyHttps: sign.resources === 'all',
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
    clearTimeout(retryTimer); clearTimeout(skipTimer);
    if (failed) {
      console.log(`[skylt] felsida visas (${overlay.offline ? 'ingen nätverksanslutning' : 'sidan gick inte att ladda'}); försöker igen om ${RETRY_MS / 1000} s: ${pages[index] ? pages[index].url.slice(0, 200) : ''}`);
      retryTimer = setTimeout(() => page.current.load(pages[index].url), RETRY_MS);
      // Finns det fler sidor går rotationen vidare till nästa efter en kort stund (felsidan står inte kvar sidans hela tid)
      if (pages.length > 1) {
        skipTimer = setTimeout(() => {
          if (page.current.failed && !page.current.ok) { console.log('[skylt] går vidare till nästa sida'); show(nextIndex(index, pages.length)); }
        }, SKIP_MS);
      }
    }
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
    if (pages.length < 2) return;
    const p = pages[index];
    const next = nextIndex(index, pages.length);
    const lead = Math.min(PRELOAD_S, Math.max(1, p.seconds - 2));
    rotateTimer = setTimeout(() => {
      views[1 - active].load(pages[next].url);
      rotateTimer = setTimeout(() => swapTo(next, 0), lead * 1000);
    }, (p.seconds - lead) * 1000);
  }

  function show(i) {
    index = i;
    views[active].load(pages[i].url);
    scheduleNext();
  }

  win.on('resize', layout);

  /** Börjar visa en spellista från första sidan (null = svart skärm) */
  function applyList(list, key) {
    clearTimeout(rotateTimer); clearTimeout(retryTimer); clearTimeout(skipTimer);
    const hadPage = pages.length > 0 && !overlay && views[active].ok; // en sida visas just nu
    listKey = key;
    pages = list || [];
    for (const v of views) { if (v !== views[active]) v.unload(); }
    if (!list) { // svart skärm: schemat säger att skylten ska vara avstängd just nu
      views[active].unload();
      overlay = null;
      for (const v of views) v.view.setVisible(false);
      layout(); push();
      return;
    }
    for (const v of views) v.view.setVisible(true);
    if (!pages.length) { // inget att visa: felsidan (utan knappar) står kvar tills inställningarna ändrats
      views[active].unload();
      overlay = { type: 'error', offline: false };
      layout(); push();
      return;
    }
    overlay = null;
    layout();
    // Vid byte från en visad lista förladdas den nya listans första sida bakom den som visas och byts in när den är klar (högst 10 s);
    // från svart skärm eller felsida börjar den direkt
    if (hadPage) {
      views[1 - active].load(pages[0].url);
      swapTo(0, 0);
    } else show(0);
  }

  /** Vilken lista ska visas just nu? Byte av lista börjar direkt på listans första sida. */
  function evaluate() {
    const now = new Date();
    const r = activeList(sign.schedule, now);
    const key = r.pages ? r.name : (r.off ? '#av' : '#standard');
    if (key === listKey) return;
    console.log(`[skylt] ${now.toTimeString().slice(0, 8)} lista: ${key === '#av' ? 'svart skärm' : key === '#standard' ? 'standardlistan' : key}`);
    applyList(r.pages ? r.pages : (r.off ? null : sign.pages), key);
  }

  evaluate();
  setInterval(evaluate, SCHEDULE_CHECK_MS);
  // En enda sida laddas om med SESSION_IDLE minuters mellanrum (som den gamla skylten)
  if (sign.reloadMin > 0) setInterval(() => { if (pages.length === 1) page.current.load(pages[0].url); }, sign.reloadMin * 60 * 1000);
};
