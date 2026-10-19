// The Electron harness of the self-test (Sources/AllInOneIME/ElectronSelfTest.swift): one window with a composer like
// Slack's (a contenteditable) and a textarea, the one named by HARNESS_FIELD focused. Its probe (probe.m, inserted with
// DYLD_INSERT_LIBRARIES) drives the window and logs what reaches the input method. Built by `make electron-harness`.
// The window is shown without taking the focus from the app in front.
const { app, BrowserWindow } = require('electron');
const path = require('path');

if (app.dock) app.dock.hide();

app.whenReady().then(() => {
  const win = new BrowserWindow({ width: 520, height: 240, x: 40, y: 40, show: false,
                                  webPreferences: { contextIsolation: true, sandbox: true, backgroundThrottling: false } });
  win.webContents.on('console-message', (event) => process.stderr.write(`[page] ${event.message ?? event}\n`));
  win.loadFile(path.join(__dirname, 'index.html'), { query: { field: process.env.HARNESS_FIELD || 'composer' } });
  win.webContents.once('did-finish-load', () => {
    win.showInactive();
    win.webContents.focus();
  });
  // The probe quits once its script is done; never later than this.
  setTimeout(() => app.quit(), 20000);
});
app.on('window-all-closed', () => app.quit());
