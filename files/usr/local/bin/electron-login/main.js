const { app, BrowserWindow, screen, ipcMain, Menu, globalShortcut } = require('electron');
const path = require('path');
const axios = require('axios');
const dotenv = require('dotenv');

dotenv.config({
  path: path.resolve(__dirname, '../config', '.config'),
  debug: false
});

const { BOOKING_TYPE, DEFAULT_BOOKING_TIME, API_URL, RESERVATION_API_URL, BOOKING_SYSTEM_URL, RESOURCE_ID, LOGINTYPE, REGISTER_ACCOUNT_URL, RESERVATION_API_CREATE_URL, RESERVATION_API_UPDATE_URL, RESERVATION_API_CURRENT_RES_URL, EXTERNAL_URL_TIMEOUT, CLEAR_FIELDS_TIMEOUT, ELECTRON_DEV_TOOLS, EXTERNAL_ALLOWED_HOSTS } = process.env;

let mainWindow;
let newWindow;
let storedUsername = '';
let inactivityTimer = null;
let inactivityClearFieldsTimer = null;
let statusUpdateInterval = null;
let authToken = null;

/**
 * Escapes text so that it can be safely inserted as HTML.
 * @param {string} text - Text from e.g. an API response.
 * @returns {string} Escaped text.
 */
function escapeHtml(text) {
    return String(text ?? '')
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}

/**
 * Hosts that external windows (book computer / register account) may navigate to.
 * The hosts of BOOKING_SYSTEM_URL and REGISTER_ACCOUNT_URL plus optional
 * comma separated EXTERNAL_ALLOWED_HOSTS from .config.
 */
const allowedExternalHosts = [BOOKING_SYSTEM_URL, REGISTER_ACCOUNT_URL]
    .map((url) => { try { return new URL(url).hostname; } catch { return null; } })
    .concat((EXTERNAL_ALLOWED_HOSTS || '').split(',').map((host) => host.trim()))
    .filter(Boolean);

function isAllowedExternalUrl(url) {
    try {
        const { protocol, hostname } = new URL(url);
        return protocol === 'https:' && allowedExternalHosts.includes(hostname);
    } catch {
        return false;
    }
}

/**
 * Verifies the user's code (PIN or password).
 * @param {string} username - The username.
 * @param {string} code - The PIN or password.
 * @returns {Promise<string>} The verification result.
 */
async function verifyCode(username, code) {
    try {
        const endpoint = LOGINTYPE === 'pin' ? API_URL : `${API_URL}?op=auth`;
        const data = LOGINTYPE === 'pin' ? { user: username, pin_number: code } : { user: username, password: code };
        const response = await axios.post(endpoint, data, { timeout: 10000 });
        switch (response.data.message) {
            //Skicka tillbaks almas primary_id om allt är ok
            case 'Success': {
                authToken = response.data.token;
                return response.data.data.primary_id;
            }
            default: return 'invalid';
        }
    } catch (error) {
        if (error.response) {
            if (error.response.status === 400) return 'invalid-username';
            if (error.response.status === 401) return 'invalid';
            if (error.response.status === 402) return 'inactive';
            if (error.response.status === 403) return 'not-non-kth';
        }
        console.error('Error: ' + error);
        return 'error';
    }
}

/**
 * Checks the reservation for a given username.
 * @param {string} username - The username.
 * @returns {Promise<Object|string>} The reservation data or an error message.
 * reservationapi: "RESERVATION_API_URL:user_id/:room_id"
 */
async function checkReservation(username) {
    try {
        const response = await axios.post(`${RESERVATION_API_URL}${username}/${RESOURCE_ID}`, {
            alma_user_id: username,
            resource_id: RESOURCE_ID,
        }, { timeout: 10000 });

        return response.data;
    } catch (error) {
        console.error('Error checking reservation:', error);
        return 'Error: Could not check reservation';
    }
}

/**
 * Checks the reservation for the current resource.
 * @returns {Promise<Object|string>} The reservation data or an error message.
 * reservationapi: "RESERVATION_API_CURRENT_RES_URL:room_id"
 */
async function checkCurrentReservationStatus() {
    try {
        const response = await axios.post(`${RESERVATION_API_CURRENT_RES_URL}${RESOURCE_ID}`, {
        }, { timeout: 10000 });

        return response.data;
    } catch (error) {
        console.error('Error checking reservation:', error);
        return 'Error: Could not check reservation';
    }
}

/**
 * Creates a reservation for a given username.
 * @param {string} room_id - The id for the computer/resource.
 * @returns {Promise<Object|string>} The reservation data or an error message.
 * reservationapi: "RESERVATION_API_CREATE_URL:room_id"
 */
async function createReservation(create_by, name, start_time, end_time) {
    try {
        const response = await axios.post(
          `${RESERVATION_API_CREATE_URL}${RESOURCE_ID}`,
          {
              create_by,
              name,
              start_time,
              end_time
          },
          {
              timeout: 10000,
              headers: {
                "Content-Type": "application/json",
                "x-access-token": authToken,
              }
          }
        );
        return response.data;
    } catch (error) {
        console.error('Error creating reservation:', error.message);
        return 'Error: Could not create reservation';
    }
}

/**
 * Updates a reservation for a given entry_id.
 * @param {string}
 * @returns {Promise<Object|string>} The reservation data or an error message.
 * reservationapi: "RESERVATION_API_UPDATE_URL:entry_i"
 */
async function resetReservation(entry_id) {
    try {
        // Sätt sluttid till nu minus 10 sekunder för att säkerställa att en kontroll inte visar att bokning finns.
        const end_time = new Date();
        const endTimestamp = Math.floor(end_time.getTime() / 1000) - 10;
        const response = await axios.post(
          `${RESERVATION_API_UPDATE_URL}${entry_id}?end_time=${endTimestamp}`,
          {},
          {
              timeout: 10000,
              headers: {
                "Content-Type": "application/json",
                "x-access-token": authToken,
              }
          }
        );
        return response.data;
    } catch (error) {
        console.error('Error updating reservation:', error);
        return 'Error: Could not update reservation';
    }
}

function startInactivityClearFieldsTimer() {
    if (inactivityClearFieldsTimer) clearTimeout(inactivityClearFieldsTimer);

    inactivityClearFieldsTimer = setTimeout(() => {
        if (mainWindow) {
            mainWindow.webContents.send('clear-fields');
        }
    }, CLEAR_FIELDS_TIMEOUT);
}

/**
 * Creates the main application window, or shows it if it already exists.
 * There is only ever one main window.
 */
function createMainWindow() {
    if (mainWindow && !mainWindow.isDestroyed()) {
        mainWindow.show();
        mainWindow.focus();
        return;
    }

    const { width, height } = screen.getPrimaryDisplay().workAreaSize;

    mainWindow = new BrowserWindow({
        width,
        height,
        frame: false,
        transparent: false,
        webPreferences: {
            preload: path.join(__dirname, 'preload.js'),
            contextIsolation: true,
            nodeIntegration: false,
            sandbox: true,
            devTools: ELECTRON_DEV_TOOLS === 'true'
        },
    });

    const dynamicComputerName = process.env.RESOURCE_ID || '1';

    mainWindow.loadFile('index.html', { query: { computername: dynamicComputerName, bookingType: BOOKING_TYPE } });

    // Inloggningssidan ska aldrig kunna navigera bort eller öppna nya fönster
    mainWindow.webContents.on('will-navigate', (event) => event.preventDefault());
    mainWindow.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));

    mainWindow.on('closed', () => {
        if (statusUpdateInterval) clearInterval(statusUpdateInterval);
        statusUpdateInterval = null;
        mainWindow = null;
    });

    mainWindow.webContents.on('did-finish-load', async() => {
        //Kontrollera om det finns en bokning
        //Görs inte för dropin-datorer
        if (BOOKING_TYPE === 'dropin') {
            //Sätt status till obokad
            mainWindow.webContents.send('current-status', {valid: false});
        } else {
            async function updateReservationStatus() {
                if (!mainWindow) return;
                const currentstatus = await checkCurrentReservationStatus();
                if (mainWindow) mainWindow.webContents.send('current-status', currentstatus);
            }
            if (statusUpdateInterval) clearInterval(statusUpdateInterval);
            updateReservationStatus();
            statusUpdateInterval = setInterval(updateReservationStatus, 10000);
        }
        mainWindow.webContents.send('load-username', storedUsername);
        const placeholder = LOGINTYPE === 'pin' ? 'PIN' : 'lösenord / password';
        mainWindow.webContents.executeJavaScript(`
            const input = document.getElementById('pin');
            if (input) input.placeholder = '${placeholder}';
        `);
    });

    mainWindow.on('close', (event) => event.preventDefault());
}

/**
 * Closes the external window (if open) and returns to the main window.
 */
function showMainWindow() {
    if (inactivityTimer) {
        clearTimeout(inactivityTimer);
        inactivityTimer = null;
    }
    if (newWindow && !newWindow.isDestroyed()) newWindow.destroy();
    newWindow = null;
    createMainWindow();
}

//Timer för att återgå till huvudfönstret om användaren är inaktiv i xxx millisekunder
function resetInactivityTimer() {
    if (inactivityTimer) clearTimeout(inactivityTimer);
    inactivityTimer = setTimeout(showMainWindow, EXTERNAL_URL_TIMEOUT);
}

/**
 * Creates a new window for external URLs or specific content.
 * @param {string} url - The URL to load.
 */
function createNewWindow(url) {
    if (newWindow && !newWindow.isDestroyed()) newWindow.destroy();

    const { width, height } = screen.getPrimaryDisplay().workAreaSize;

    newWindow = new BrowserWindow({
        width,
        height,
        frame: false,
        webPreferences: {
            preload: path.join(__dirname, 'preload.js'),
            contextIsolation: true,
            nodeIntegration: false,
            sandbox: true,
            devTools: ELECTRON_DEV_TOOLS === 'true'
        },
    });

    // Tillåt bara navigering inom bokningssystemet/registreringsformuläret,
    // så att det inte går att ta sig ut på internet från inloggningsskärmen
    const blockDisallowed = (event, targetUrl) => {
        if (!isAllowedExternalUrl(targetUrl)) {
            console.error('Blocked navigation to ' + targetUrl);
            event.preventDefault();
        }
    };
    newWindow.webContents.on('will-navigate', blockDisallowed);
    newWindow.webContents.on('will-redirect', blockDisallowed);
    newWindow.webContents.setWindowOpenHandler(({ url: targetUrl }) => {
        // Länkar som vill öppna nytt fönster öppnas i samma fönster om de är tillåtna
        if (isAllowedExternalUrl(targetUrl)) newWindow.loadURL(targetUrl);
        return { action: 'deny' };
    });

    newWindow.loadURL(url);

    newWindow.webContents.on('did-navigate', (event, currentUrl) => {
        if (currentUrl !== `file://${path.join(__dirname, 'index.html')}`) injectExternalScript(newWindow);
    });

    const thisWindow = newWindow;
    thisWindow.on('closed', () => {
        if (newWindow === thisWindow) {
            newWindow = null;
            if (inactivityTimer) clearTimeout(inactivityTimer);
            inactivityTimer = null;
        }
    });

    injectExternalScript(newWindow);

    newWindow.on('focus', resetInactivityTimer);

    resetInactivityTimer();
}

/**
 * Injects a back button into the window.
 * @param {BrowserWindow} window - The window where the button will be injected.
 */
function injectExternalScript(window) {
    window.webContents.executeJavaScript(`
        if (!document.getElementById('back-button')) {
        const style = document.createElement('style');
        style.innerHTML = 'form { padding: 10px; }';
        document.head.appendChild(style);
        const backButton = document.createElement('button');
        backButton.id = 'back-button';
        backButton.innerHTML = '<i class="fas fa-home" style="color: #ffffff26; font-size: 70px; position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%);"></i><span style="font-size: 16px; font-weight: 700">Back to login</span>';
        backButton.style.position = 'relative';
        backButton.style.top = '10px';
        backButton.style.left = '10px';
        backButton.style.padding = '10px';
        backButton.style.width = '130px';
        backButton.style.height = '80px';
        backButton.style.backgroundColor = '#007bff';
        backButton.style.color = 'white';
        backButton.style.border = 'none';
        backButton.style.borderRadius = '5px';
        backButton.style.cursor = 'pointer';
        backButton.style.zIndex = '1001';

        const backgroundDiv = document.createElement('div');
        backgroundDiv.id = 'background-div';
        backgroundDiv.style.position = 'relative';
        backgroundDiv.style.top = '0';
        backgroundDiv.style.left = '0';
        backgroundDiv.style.width = '100%';
        backgroundDiv.style.height = '100px';
        backgroundDiv.style.backgroundColor = '#000061';
        backgroundDiv.style.zIndex = '1000';

        document.body.style.margin = '0'; // Ensure no margins interfere with the button
        document.body.style.padding = '0px';
        document.body.insertBefore(backgroundDiv, document.body.firstChild);
        backgroundDiv.appendChild(backButton);

        // Add click event to send an IPC message
        backButton.addEventListener('click', () => {
            window.electron.ipcRenderer.send('back-to-main');
        });

        // Detect mousemove, wheel, and keydown events
        document.addEventListener('mousemove', () => {
            window.electron.ipcRenderer.send('user-activity');
        });

        document.addEventListener('wheel', () => {
            window.electron.ipcRenderer.send('user-activity');
        });

        document.addEventListener('keydown', () => {
            window.electron.ipcRenderer.send('user-activity');
        });

        // Optionally detect clicks or any other interactions
        document.addEventListener('click', () => {
            window.electron.ipcRenderer.send('user-activity');
        });

        // Add Font Awesome link
        var link = document.createElement('link');
        link.rel = 'stylesheet';
        link.href = 'https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0-beta3/css/all.min.css';
        document.head.appendChild(link);
    }
    `);
}

/**
 * Event handlers for IPC communication.
 */
function setupIPC() {
    // Kanaler för inloggningen får bara användas av huvudfönstret, inte av externa sidor
    const fromMainWindow = (event) => mainWindow && event.sender === mainWindow.webContents;

    ipcMain.on('submit-form', async (event, username, pin) => {
        if (!fromMainWindow(event)) return;
        mainWindow.webContents.send('spinner-start', ``);
        const verificationResult = await verifyCode(username, pin);
        let message_en
        let message_sv
        switch (verificationResult) {
            case 'invalid-username':
                mainWindow.webContents.send('spinner-remove', ``);
                mainWindow.webContents.send('user-message', '<div class="kth-alert warning"><h2>Invalid username. / Fel användarnamn.</h2> <p>Please try again. / Försök igen.</p>');
                break;
            case 'invalid':
                message_en = LOGINTYPE === 'pin' ? 'Invalid Username/PIN' : 'Invalid Username/Password';
                message_sv = LOGINTYPE === 'pin' ? 'Fel Username/PIN' : 'Fel Username/Password';
                mainWindow.webContents.send('spinner-remove', ``);
                mainWindow.webContents.send('user-message', `<div class="kth-alert warning"><h2>Info</h2><p>${message_en}. Please try again.</p><p>${message_sv}. Försök igen.</p>`);
                break;
            case 'not-non-kth':
                message_en = 'Only external users can login';
                message_sv = 'Endast externa användare kan logga in';
                mainWindow.webContents.send('spinner-remove', ``);
                mainWindow.webContents.send('user-message', `<div class="kth-alert warning"><h2>Info</h2><p>${message_en}</p><p>${message_sv}</p>`);
                break;
            case 'inactive':
                message_en = 'You need to activate your account, contact the library.';
                message_sv = 'Du måste aktivera ditt konto, kontakta biblioteket.';
                mainWindow.webContents.send('spinner-remove', ``);
                mainWindow.webContents.send('user-message', `<div class="kth-alert warning"><h2>Info</h2><p>${message_en}</p><p>${message_sv}</p>`);
                break;
            case 'error':
                mainWindow.webContents.send('spinner-remove', ``);
                mainWindow.webContents.send('user-message', '<div class="kth-alert warning"><h2>An error occurred. Please try again. / Ett fel uppstod. Försök igen.</h2><p>If the error persists contact the info desk. / Om felet kvarstår kontakta informationsdisken.</p>');
                break;
            default:

                // Avsluta(sätt sluttid) eventuell befintlig bokning på Dropin-datorer
                if(BOOKING_TYPE==='dropin') {
                    const status = await checkCurrentReservationStatus()
                    if (status.valid) {
                        const resetBooking = await resetReservation(status.reservation.id);
                    }
                }
                const reservationstatus = await checkCurrentReservationStatus()
                let reservation
                if (!reservationstatus.valid) {
                  // Om datorn är ledig
                  // Skapa en bokning för användaren med starttid som är nuvarande tids timme.
                  // t ex om kl är 12:23 så ska start_time vara 12:00
                  // end_time ska vara start_time + x timmar
                  const start_time = new Date();
                  //start_time.setMinutes(0);
                  //start_time.setSeconds(0);
                  start_time.setMilliseconds(0);
                  const end_time = new Date(start_time);
                  end_time.setHours(start_time.getHours() + parseInt(DEFAULT_BOOKING_TIME, 10));
                  const startTimestamp = Math.floor(start_time.getTime() / 1000);
                  const endTimestamp = Math.floor(end_time.getTime() / 1000);
                  reservation = await createReservation(username, username, startTimestamp, endTimestamp);
                } else {
                  // Om datorn är upptagen
                  // Kolla bokning med det primary_id som alma returnerar för en giltig bokning
                  reservation = await checkReservation(verificationResult);
                }
               if (reservation.valid) {
                    mainWindow.webContents.send('spinner-remove', ``);
                    //Skickar data tillbaks till anropande shell-script
                    console.log(JSON.stringify({ booking_data: reservation.reservation }));
                    process.exit(0);
                } else {
                    // Texten kommer från API:t och escapas innan den visas som HTML
                    const apiMessage = escapeHtml(reservation.message || reservation);
                    mainWindow.webContents.send('spinner-remove', ``);
                    mainWindow.webContents.send('user-message', `<div class="kth-alert warning"> <h2>Login/booking failed</h2> <p>${apiMessage}</p></div>`);
                }
        }
    });

    ipcMain.on('load-username', (event, username) => {
        if (!fromMainWindow(event)) return;
        storedUsername = username;
        mainWindow.webContents.send('load-username', storedUsername);
    });

    ipcMain.on('load-external-url', (event, type) => {
        if (!fromMainWindow(event)) return;
        if(type === 'book-computer') {
            createNewWindow(BOOKING_SYSTEM_URL + '?room=' + RESOURCE_ID);
            return;
        }

        if(type === 'register-account') {
            createNewWindow(REGISTER_ACCOUNT_URL);
            return;
        }

    });

    ipcMain.on('back-to-main', () => {
        showMainWindow();
    });

    // Aktivitet i externt fönster förlänger dess timeout, aktivitet i huvudfönstret
    // skjuter upp rensningen av inloggningsfälten
    ipcMain.on('user-activity', (event) => {
        if (newWindow && event.sender === newWindow.webContents) {
            resetInactivityTimer();
        } else {
            startInactivityClearFieldsTimer();
        }
    });
}

/**
 * App lifecycle events.
 */
app.whenReady().then(() => {
    const argv = process.argv.slice(1);
    storedUsername = argv[1] || '';
    createMainWindow();
    setupIPC();
});

app.on('window-all-closed', () => {
    if (process.platform !== 'darwin') app.quit();
});
