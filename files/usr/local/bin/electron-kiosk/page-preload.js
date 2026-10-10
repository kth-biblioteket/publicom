// Körs i sidvyn (sandbox, isolerad värld). Rapporterar bara om ett redigerbart fält får fokus.
// Sidan kan inte anropa något härifrån, inget exponeras i sidans värld.
const { ipcRenderer, webFrame } = require('electron');

// PRINTER=false: window.print() gör ingenting. Ctrl+P blockeras i main.js.
if (!ipcRenderer.sendSync('page:cfg').printing) webFrame.executeJavaScript('window.print = function () {};');

function fieldType(el) {
  if (!el || el.nodeType !== 1) return null;
  if (el.tagName === 'TEXTAREA') return 'text';
  if (el.tagName === 'INPUT') {
    const t = (el.type || 'text').toLowerCase();
    if (t === 'email') return 'email';
    if (t === 'number' || t === 'tel') return 'number';
    if (['text', 'search', 'url', 'password'].includes(t)) return 'text';
    return null;
  }
  return el.isContentEditable ? 'text' : null;
}
const target = (e) => (e.composedPath && e.composedPath()[0]) || e.target; // även i öppna shadow roots

// Vad Retur-knappen ska heta: bara sökfält får "Sök"; kan det inte avgöras blir det "Retur".
function enterKind(el) {
  const hint = (el.getAttribute('enterkeyhint') || '').toLowerCase();
  if (['search', 'go', 'send', 'done', 'next'].includes(hint)) return hint;
  if (el.tagName === 'TEXTAREA' || el.isContentEditable) return 'enter';
  if (el.tagName === 'INPUT' && (el.type || '').toLowerCase() === 'search') return 'search';
  if ((el.getAttribute('role') || '').toLowerCase() === 'searchbox') return 'search';
  if (el.closest && el.closest('[role="search"]')) return 'search';
  return 'enter';
}

window.addEventListener('focusin', (e) => {
  const el = target(e);
  const type = fieldType(el);
  const info = type ? {
    tag: el.tagName, inputType: el.type || null, role: el.getAttribute('role'), id: el.id || null,
    name: el.getAttribute('name'), hint: el.getAttribute('enterkeyhint'),
    frame: window === window.top ? 'huvudram' : 'underram',
  } : null;
  // Fokus som sidan själv sätter (autofocus när sidan laddas) visar inte tangentbordet, som på en telefon.
  // Bara fokus efter att användaren nyss rört något (tryck, tangent) räknas.
  if (type && navigator.userActivation && !navigator.userActivation.isActive) {
    ipcRenderer.send('field-auto', info);
    return;
  }
  ipcRenderer.send(type ? 'field-focus' : 'field-away', { type, enter: type ? enterKind(el) : null, info });
}, true);
// Ett tryck i ett fält visar tangentbordet även när fältet redan har fokus (efter Fäll ner eller Sök)
window.addEventListener('pointerdown', (e) => {
  const el = target(e);
  const type = fieldType(el);
  if (type) ipcRenderer.send('field-focus', { type, enter: enterKind(el), info: null, tap: true });
  else ipcRenderer.send('field-away');
}, true);
