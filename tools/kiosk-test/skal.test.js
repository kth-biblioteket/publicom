'use strict';
// Enhetstester för kioskskalets rena logik. Körs av tools/check.sh: node --test tools/kiosk-test
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const dir = path.join(__dirname, '..', '..', 'files', 'usr', 'local', 'bin', 'electron-kiosk');
const { parseEnv, parseApps, buildSettings, Scope, MAX_APPS } = require(path.join(dir, 'config.js'));
const { UrlPolicy, normalize } = require(path.join(dir, 'policy.js'));
const { idleState } = require(path.join(dir, 'idle.js'));
const { stringsFor, pick } = require(path.join(dir, 'strings.js'));

test('parseEnv: som load_config, inget körs och citattecken tas bort', () => {
  const env = parseEnv('A="x y"\nB=\'z\'\n# c\nC=$(rm -rf /)\n1X=no\nexport D=no\nE=ok\r\nF="en|två"\n');
  assert.equal(env.A, 'x y');
  assert.equal(env.B, 'z');
  assert.equal(env.C, '$(rm -rf /)'); // ordagrant, körs aldrig
  assert.equal(env['1X'], undefined);
  assert.equal(env['export D'], undefined);
  assert.equal(env.E, 'ok');
  assert.equal(env.F, 'en|två');
});

test('parseApps: radform med alla sju delar', () => {
  const [a] = parseApps('Sök böcker|https://primo.example.se/x/|search|primo.example.se/x/|Hitta böcker.|Search books|Find books.');
  assert.equal(a.label, 'Sök böcker');
  assert.equal(a.icon, 'search');
  assert.equal(a.nameFor(true), 'Search books');
  assert.equal(a.descFor(true), 'Find books.');
  assert.equal(a.descFor(false), 'Hitta böcker.');
  assert.ok(a.scope.contains('https://primo.example.se/x/y'));
  assert.ok(!a.scope.contains('https://primo.example.se/annat'));
});

test('parseApps: engelska faller tillbaka på svenska, och bara namn och adress krävs', () => {
  const [a] = parseApps('Karta|https://karta.example.se/');
  assert.equal(a.nameFor(true), 'Karta');
  assert.equal(a.descFor(true), '');
});

test('parseApps: JSON-form med tecken som annars förstör raderna', () => {
  const apps = parseApps(JSON.stringify([{ name: 'A | B', url: 'https://a.example.se/', desc: 'rad 1\nrad 2', nameEn: 'A and B' }]));
  assert.equal(apps.length, 1);
  assert.equal(apps[0].label, 'A | B');
  assert.equal(apps[0].desc, 'rad 1\nrad 2');
  assert.equal(apps[0].nameFor(true), 'A and B');
});

test('parseApps: ogiltiga poster hoppas över, http är ogiltigt, tak på sex', () => {
  const raw = ['Ok|https://ok.example.se/', 'Http|http://nej.example.se/', 'Utan adress', '|https://tomt.example.se/'].join('\n');
  assert.deepEqual(parseApps(raw).map((a) => a.label), ['Ok']);
  const many = Array.from({ length: 9 }, (_, i) => `T${i}|https://t${i}.example.se/`).join('\n');
  assert.equal(parseApps(many).length, MAX_APPS);
});

test('parseApps: bokstavlig \\n och komma fungerar när värdet står på en rad i .config', () => {
  assert.equal(parseApps('A|https://a.example.se/\\nB|https://b.example.se/').length, 2);
  assert.equal(parseApps('A|https://a.example.se/,B|https://b.example.se/').length, 2);
});

test('parseApps: trasig JSON tolkas som rader', () => {
  assert.deepEqual(parseApps('[Sök|https://a.example.se/').map((a) => a.label), ['[Sök']);
  assert.deepEqual(parseApps('[{"name":').map((a) => a.label), []);
});

test('Scope: katalog av adressen, filnamn räknas inte som katalog', () => {
  assert.equal(Scope.fromStartUrl('https://x.se/kiosk').prefix, '/kiosk/');
  assert.equal(Scope.fromStartUrl('https://x.se/app/index.html').prefix, '/app/');
  assert.equal(Scope.parse('x.se/a/b').prefix, '/a/b/');
  assert.equal(Scope.parse(''), null);
});

test('UrlPolicy: https mot tillåtna värdar och deras underdomäner, annars blockerat', () => {
  const apps = parseApps('P|https://primo.example.se/');
  const p = new UrlPolicy(apps, ['kth.se', '*.exlibris.com', 'https://libris.kb.se/x', 'ogiltigt']);
  assert.ok(p.allows('https://primo.example.se/a'));
  assert.ok(p.allows('https://www.kth.se/'));
  assert.ok(p.allows('https://x.exlibris.com/'));
  assert.ok(p.allows('https://libris.kb.se/'));
  assert.ok(!p.allows('https://notkth.se/'));
  assert.ok(!p.allows('https://kth.se.evil.com/'));
  assert.ok(!p.allows('http://www.kth.se/'));
  for (const bad of ['file:///etc/passwd', 'data:text/html,x', 'javascript:alert(1)', 'intent://x', 'about:blank', '', null, 'inte en adress']) {
    assert.ok(!p.allows(bad), String(bad));
  }
});

test('UrlPolicy: http uppgraderas bara till tillåten värd', () => {
  const p = new UrlPolicy([], ['kth.se']);
  assert.equal(p.httpsUpgrade('http://www.kth.se/a?b=1'), 'https://www.kth.se/a?b=1');
  assert.equal(p.httpsUpgrade('http://annan.se/'), null);
  assert.equal(p.httpsUpgrade('https://www.kth.se/'), null);
});

test('normalize', () => {
  assert.equal(normalize('https://www.kth.se/x'), 'www.kth.se');
  assert.equal(normalize('*.kth.se'), 'kth.se');
  assert.equal(normalize('kth.se:443/x'), 'kth.se');
  assert.equal(normalize('localhost'), null);
});

test('idleState: aktiv, varning, återställd, och 0 betyder aldrig', () => {
  assert.equal(idleState(10, 0, 60).state, 'active');
  assert.equal(idleState(100, 300, 60).state, 'active');
  assert.deepEqual(idleState(240, 300, 60), { state: 'warning', secondsLeft: 60 });
  assert.equal(idleState(299, 300, 60).secondsLeft, 1);
  assert.equal(idleState(300, 300, 60).state, 'expired');
  assert.equal(idleState(5, 30, 60).state, 'warning'); // varningstiden längre än sessionen
  assert.equal(idleState(250, 300, 0).state, 'active');
});

test('buildSettings: standardvärden, WEBSITES som reserv och värdlistan', () => {
  const s = buildSettings({ WEBSITES: 'https://www.primo.example.se/a https://b.example.se/', WHITE_LIST: 'kth.se,exlibris.com', SESSION_IDLE: '3' }, 'jstor.org\n# c\n\nwiley.com\n');
  assert.deepEqual(s.apps.map((a) => a.label), ['primo.example.se', 'b.example.se']);
  assert.equal(s.homeMode, 'launcher');
  assert.equal(s.sessionSec, 180);
  assert.equal(s.warnSec, 60);
  assert.equal(s.printing, false);
  assert.equal(s.downloads, false);
  assert.deepEqual(s.allowedHosts, ['kth.se', 'exlibris.com', 'jstor.org', 'wiley.com']);
  const s2 = buildSettings({ HOME_MODE: 'app', LANGUAGE: 'en', NAVIGATION: 'false', PRINTER: 'true', DOWNLOADS: 'true' }, '');
  assert.equal(s2.homeMode, 'app');
  assert.equal(s2.language, 'en');
  assert.equal(s2.navigation, false);
  assert.equal(s2.printing, true);
  assert.equal(s2.downloads, true);
});

test('strings: pick och språk', () => {
  assert.equal(pick('sv', 'Hej', 'Hello', 'x'), 'Hej');
  assert.equal(pick('en', 'Hej', 'Hello', 'x'), 'Hello');
  assert.equal(pick('en', 'Hej', '', 'x'), 'Hej');
  assert.equal(pick('sv', '', '', 'standard'), 'standard');
  assert.match(stringsFor('en', 12).idleText, /In 12 seconds/);
  assert.equal(stringsFor('sv').back, 'Tillbaka');
});
