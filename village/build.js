// Builds village/index.html: splices the vendored three.js runtime, the character
// rig and every src/*.js module into index.template.html, producing one
// self-contained file with zero external requests (works from file://, from a
// static host, and inside a CSP-locked Artifact frame alike).
//
// Run: node build.js
const fs = require('fs');
const path = require('path');

const dir = __dirname;
const srcDir = path.join(dir, 'src');
// three.js and the rig live in web-prototype/ and are shared rather than
// duplicated — 3 MB of binary has no business existing twice in one repo.
const shared = path.join(dir, '..', 'web-prototype');

const modules = fs.readdirSync(srcDir).filter(f => f.endsWith('.js')).sort();
if (!modules.length) throw new Error('src/ has no .js modules');

const game = modules
  .map(f => `\n// ===== src/${f} ${'='.repeat(Math.max(0, 60 - f.length))}\n` + fs.readFileSync(path.join(srcDir, f), 'utf8'))
  .join('\n');

const replacements = [
  ['<!--THREE_JS_SOURCE-->', () => fs.readFileSync(path.join(shared, 'three.min.js'), 'utf8')],
  ['<!--GLTFLOADER_JS_SOURCE-->', () => fs.readFileSync(path.join(shared, 'vendor', 'GLTFLoader.js'), 'utf8')],
  ['<!--SKELETONUTILS_JS_SOURCE-->', () => fs.readFileSync(path.join(shared, 'vendor', 'SkeletonUtils.js'), 'utf8')],
  ['<!--SOLDIER_GLB_BASE64-->', () => fs.readFileSync(path.join(shared, 'vendor', 'Soldier.glb')).toString('base64')],
  ['<!--GAME_SOURCE-->', () => game],
];

let output = fs.readFileSync(path.join(dir, 'index.template.html'), 'utf8');
for (const [marker, getContent] of replacements) {
  if (!output.includes(marker)) throw new Error(`marker ${marker} not found in index.template.html`);
  output = output.replace(marker, getContent);
}

fs.writeFileSync(path.join(dir, 'index.html'), output);
console.log(`Wrote index.html (${(output.length / 1024 / 1024).toFixed(2)} MB) from ${modules.length} modules:`);
for (const m of modules) console.log('  · ' + m);
