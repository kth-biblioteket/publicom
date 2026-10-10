'use strict';
// Inaktivitet: varning en stund före återställning. Ren funktion som testas med node --test.
// idleSec: sekunder sedan senaste aktivitet. sessionSec: 0 betyder aldrig.
function idleState(idleSec, sessionSec, warnSec) {
  if (!(sessionSec > 0)) return { state: 'active', secondsLeft: 0 };
  const warnStart = Math.max(0, sessionSec - Math.max(0, warnSec));
  if (idleSec >= sessionSec) return { state: 'expired', secondsLeft: 0 };
  if (warnSec > 0 && idleSec >= warnStart) return { state: 'warning', secondsLeft: Math.ceil(sessionSec - idleSec) };
  return { state: 'active', secondsLeft: Math.ceil(sessionSec - idleSec) };
}

module.exports = { idleState };
