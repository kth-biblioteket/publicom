'use strict';
// Texter för skalets egna sidor, svenska och engelska. Tjänsternas namn och beskrivningar kommer från APPS.
const SV = {
  org: 'KTH Biblioteket',
  langSwitch: 'English',
  title: 'Vad vill du göra?',
  subtitle: 'Tryck på en tjänst för att börja.',
  back: 'Tillbaka',
  start: 'Startsida',
  idleTitle: 'Är du kvar?',
  idleText: (s) => `Ingen har rört skärmen på en stund. Om ${s} sekunder börjar appen om från början och det du har gjort här rensas.`,
  idleContinue: 'Fortsätt här',
  idleRestart: 'Börja om nu',
  blockedTitle: 'Sidan kan inte öppnas här',
  blockedText: 'Den här länken kan inte öppnas på skärmen.',
  blockedQr: 'Skanna koden med din mobil för att fortsätta där.',
  close: 'Stäng',
  errorTitle: 'Sidan kunde inte laddas',
  errorText: 'Det kan vara ett tillfälligt nätverksfel. Försök igen, eller börja om från början.',
  offlineTitle: 'Väntar på nätverket…',
  offlineText: 'Sidan laddas av sig själv så snart skärmen är ansluten.',
  retry: 'Försök igen',
  startOver: 'Börja om',
};
const EN = {
  org: 'KTH Library',
  langSwitch: 'Svenska',
  title: 'What do you need?',
  subtitle: 'Tap a service to begin.',
  back: 'Back',
  start: 'Home',
  idleTitle: 'Are you still there?',
  idleText: (s) => `Nobody has touched the screen for a while. In ${s} seconds the app starts over and what you did here is cleared.`,
  idleContinue: 'Continue here',
  idleRestart: 'Start over now',
  blockedTitle: "This page can't be opened here",
  blockedText: "This link can't be opened on this screen.",
  blockedQr: 'Scan the code with your phone to continue there.',
  close: 'Close',
  errorTitle: 'The page could not be loaded',
  errorText: 'It may be a temporary network problem. Try again, or start over.',
  offlineTitle: 'Waiting for the network…',
  offlineText: 'The page loads by itself as soon as the screen is connected.',
  retry: 'Try again',
  startOver: 'Start over',
};

/** Texterna på valt språk, färdiga att skicka till skalets sidor (funktioner ersatta av värden) */
function stringsFor(lang, idleSecondsLeft) {
  const t = lang === 'en' ? EN : SV;
  const out = {};
  for (const k of Object.keys(t)) out[k] = typeof t[k] === 'function' ? t[k](idleSecondsLeft || 0) : t[k];
  return out;
}

/** Inställningstext på valt språk: den engelska, annars den svenska, annars standardtexten */
function pick(lang, sv, en, fallback) {
  if (lang === 'en' && en) return en;
  return sv || (lang === 'en' ? en : '') || fallback;
}

module.exports = { stringsFor, pick };
