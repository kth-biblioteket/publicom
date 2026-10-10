// Gemensam preload för skalets egna sidor (förstasida, navigering, överlägg). Sidorna får bara
// läsa tillståndet och be om några få, namngivna åtgärder; main.js kontrollerar dem igen.
const { contextBridge, ipcRenderer } = require('electron');
// Synlig återkoppling direkt vid tryck, även om skärmen är långsam: knappen får klassen "down" en stund
window.addEventListener('pointerdown', (e) => {
  const b = e.target && e.target.closest && e.target.closest('button');
  if (!b || b.disabled) return;
  b.classList.add('down');
  setTimeout(() => b.classList.remove('down'), 200);
}, true);

contextBridge.exposeInMainWorld('kiosk', {
  state: () => ipcRenderer.invoke('ui:state'),
  onState: (cb) => ipcRenderer.on('ui:state', (_e, s) => cb(s)),
  act: (name, arg) => ipcRenderer.send('ui:act', name, arg),
});
