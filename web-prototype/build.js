// Splices the vendored three.js build into index.template.html to produce a
// single self-contained index.html (no external <script src> requests).
// Run: node build.js   (three.min.js must sit next to this file)
const fs = require('fs');
const path = require('path');

const dir = __dirname;
const template = fs.readFileSync(path.join(dir, 'index.template.html'), 'utf8');
const threeSrc = fs.readFileSync(path.join(dir, 'three.min.js'), 'utf8');

const marker = '<!--THREE_JS_SOURCE-->';
if (!template.includes(marker)) {
  throw new Error(`marker ${marker} not found in index.template.html`);
}

const output = template.replace(marker, threeSrc);
fs.writeFileSync(path.join(dir, 'index.html'), output);
console.log(`Wrote index.html (${(output.length / 1024).toFixed(0)} KB)`);
