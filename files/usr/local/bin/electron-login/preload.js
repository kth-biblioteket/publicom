const { contextBridge, ipcRenderer } = require('electron');

// Endast dessa kanaler exponeras för sidorna. main.js kontrollerar dessutom
// att inloggningskanalerna bara används av huvudfönstret.
const SEND_CHANNELS = ['submit-form', 'load-username', 'load-external-url', 'back-to-main', 'user-activity'];
const RECEIVE_CHANNELS = ['clear-fields', 'current-status', 'load-username', 'user-message', 'spinner-start', 'spinner-remove'];

contextBridge.exposeInMainWorld('electron', {
    ipcRenderer: {
        send: (channel, ...args) => {
            if (SEND_CHANNELS.includes(channel)) ipcRenderer.send(channel, ...args);
        },
        on: (channel, func) => {
            if (RECEIVE_CHANNELS.includes(channel)) ipcRenderer.on(channel, (event, ...args) => func(...args));
        }
    }
});
