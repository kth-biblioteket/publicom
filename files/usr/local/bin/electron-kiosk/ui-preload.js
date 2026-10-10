// Gemensam preload för skalets egna sidor (förstasida, navigering, överlägg). Sidorna får bara
// läsa tillståndet och be om några få, namngivna åtgärder; main.js kontrollerar dem igen.
const { contextBridge, ipcRenderer } = require('electron');
contextBridge.exposeInMainWorld('kiosk', {
  state: () => ipcRenderer.invoke('ui:state'),
  onState: (cb) => ipcRenderer.on('ui:state', (_e, s) => cb(s)),
  act: (name, arg) => ipcRenderer.send('ui:act', name, arg),
});
