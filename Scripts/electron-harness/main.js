// The Electron harness of the self-test (Sources/AllInOneIME/ElectronSelfTest.swift): one window with a composer like
// Slack's (a contenteditable) and a textarea, the one named by HARNESS_FIELD focused. Its probe (probe.m, inserted with
// DYLD_INSERT_LIBRARIES) drives the window and logs what reaches the input method. Built by `make electron-harness`.
// The window is shown without taking the focus from the app in front. HARNESS_BUSY: milliseconds the page takes over
// each key down, as a busy page (Slack's) does; none without it. HARNESS_USER_DATA: the folder Electron keeps its data
// in (the self-test gives it a temporary one); without it, Electron's own under ~/Library/Application Support.
const { app, BrowserWindow } = require('electron');
const path = require('path');

if (process.env.HARNESS_USER_DATA) app.setPath('userData', process.env.HARNESS_USER_DATA);
if (app.dock) app.dock.hide();

app.whenReady().then(() => {
  const win = new BrowserWindow({ width: 520, height: 240, x: 40, y: 40, show: false,
                                  webPreferences: { contextIsolation: true, sandbox: true, backgroundThrottling: false } });
  win.webContents.on('console-message', (event) => {
    const message = `${event.message ?? event}`;
    process.stderr.write(`[page] ${message}\n`);
    // What the page says for the self-test ("PAGE …", index.html) on stdout too, with the probe's lines.
    if (message.startsWith('PAGE ')) process.stdout.write(`${message}\n`);
  });
  win.loadFile(path.join(__dirname, 'index.html'),
               { query: { field: process.env.HARNESS_FIELD || 'composer', busy: process.env.HARNESS_BUSY || '0' } });
  win.webContents.once('did-finish-load', () => {
    win.showInactive();
    win.webContents.focus();
  });
  // The probe quits once its script is done; never later than this.
  setTimeout(() => app.quit(), 20000);
});
app.on('window-all-closed', () => app.quit());
