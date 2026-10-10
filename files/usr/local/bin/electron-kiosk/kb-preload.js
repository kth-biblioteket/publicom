const { contextBridge, ipcRenderer } = require('electron');
contextBridge.exposeInMainWorld('kb', {
  send: (m) => ipcRenderer.send('kb', m),
  onLayout: (cb) => ipcRenderer.on('layout', (_e, m) => cb(m)),
});
