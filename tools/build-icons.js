#!/usr/bin/env node
'use strict';
// Bygger files/usr/local/bin/electron-kiosk/icons.js ur Lucide (ISC) oförändrat från paketet lucide-static.
// Används bara när ikonerna uppdateras, aldrig på datorerna (inget hämtas i drift):
//   npm pack lucide-static@1.48.0 && mkdir x && tar xzf lucide-static-1.48.0.tgz -C x
//   node tools/build-icons.js x/package files/usr/local/bin/electron-kiosk
// Alla icons/*.svg tas med, aliasen (t.ex. circle-help) också. Likadana ikoner lagras en gång.
const fs = require('fs');
const path = require('path');

const [pkgDir, outDir] = process.argv.slice(2);
if (!pkgDir || !outDir) { console.error('användning: build-icons.js <lucide-static-katalog> <utkatalog>'); process.exit(2); }
const version = JSON.parse(fs.readFileSync(path.join(pkgDir, 'package.json'), 'utf8')).version;
const iconsDir = path.join(pkgDir, 'icons');
const names = fs.readdirSync(iconsDir).filter((f) => f.endsWith('.svg')).map((f) => f.slice(0, -4)).sort();

const TAGS = 'path|circle|rect|line|polyline|polygon|ellipse';
const bodies = new Map(); // markup -> [namn]
for (const n of names) {
  const svg = fs.readFileSync(path.join(iconsDir, n + '.svg'), 'utf8').replace(/<!--[\s\S]*?-->/g, '');
  const inner = svg.slice(svg.indexOf('>', svg.indexOf('<svg')) + 1, svg.lastIndexOf('</svg>'));
  const els = [...inner.matchAll(new RegExp('<(' + TAGS + ')\\b([^>]*?)\\s*/>', 'g'))].map((m) => '<' + m[1] + m[2].replace(/\s+/g, ' ').replace(/\s*$/, '') + '/>');
  const rest = inner.replace(new RegExp('<(' + TAGS + ')\\b[^>]*?/>', 'g'), '').trim();
  if (!els.length || rest) throw new Error(n + ': oväntat innehåll i ' + n + '.svg: ' + rest.slice(0, 80));
  const body = els.join('');
  if (!bodies.has(body)) bodies.set(body, []);
  bodies.get(body).push(n);
}

let out = '// Lucide ' + version + ' (ISC, se icons-LICENSE.txt), oförändrat från lucide-static. Genererad av tools/build-icons.js, redigera inte för hand.\n' +
  "'use strict';\nconst ICONS = {\n";
const rows = [];
for (const [body, ns] of bodies) for (const n of ns) rows.push([n, body]);
rows.sort((a, b) => (a[0] < b[0] ? -1 : 1));
out += rows.map(([n, b]) => ' ' + JSON.stringify(n) + ': ' + JSON.stringify(b)).join(',\n') + '\n};\n';
out += `
/** Ikonen som SVG (Lucide, linje 2.2, utan fyllning). Okänt eller tomt namn ger info. */
function iconSvg(name, size, extraStyle) {
  const body = ICONS[String(name || '').trim().toLowerCase()] || ICONS.info;
  return '<svg width="' + size + '" height="' + size + '" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"' + (extraStyle ? ' style="' + extraStyle + '"' : '') + '>' + body + '</svg>';
}

if (typeof module !== 'undefined') module.exports = { ICONS, iconSvg };
`;
fs.writeFileSync(path.join(outDir, 'icons.js'), out);
fs.copyFileSync(path.join(pkgDir, 'LICENSE'), path.join(outDir, 'icons-LICENSE.txt'));
console.log(names.length + ' ikoner, ' + (out.length / 1024).toFixed(0) + ' kB');
