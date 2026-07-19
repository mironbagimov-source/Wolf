// Splices the vendored three.js build + character models into
// index.template.html to produce a single self-contained index.html with
// zero external requests (Artifact CSP blocks CDN scripts and remote
// fetches; everything has to already be in the file).
// Run: node build.js   (vendor/ assets must sit next to this file)
const fs = require('fs');
const path = require('path');

const dir = __dirname;
const vendor = path.join(dir, 'vendor');
const template = fs.readFileSync(path.join(dir, 'index.template.html'), 'utf8');

const replacements = [
  ['<!--THREE_JS_SOURCE-->', () => fs.readFileSync(path.join(dir, 'three.min.js'), 'utf8')],
  ['<!--GLTFLOADER_JS_SOURCE-->', () => fs.readFileSync(path.join(vendor, 'GLTFLoader.js'), 'utf8')],
  ['<!--SKELETONUTILS_JS_SOURCE-->', () => fs.readFileSync(path.join(vendor, 'SkeletonUtils.js'), 'utf8')],
  ['<!--SOLDIER_GLB_BASE64-->', () => fs.readFileSync(path.join(vendor, 'Soldier.glb')).toString('base64')],
];

let output = template;
for (const [marker, getContent] of replacements) {
  if (!output.includes(marker)) {
    throw new Error(`marker ${marker} not found in index.template.html`);
  }
  output = output.replace(marker, getContent);
}

fs.writeFileSync(path.join(dir, 'index.html'), output);
console.log(`Wrote index.html (${(output.length / 1024 / 1024).toFixed(2)} MB)`);
