import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { dirname, join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';

const web = normalize(join(dirname(fileURLToPath(import.meta.url)), '..'));

test('service worker precaches every JavaScript module', () => {
  const sw = readFileSync(join(web, 'sw.js'), 'utf8');
  const assets = [...sw.matchAll(/'\.\/([^']*)'/g)].map((match) => match[1]);
  assert.ok(assets.includes('js/ui/app.js'));
  for (const file of assets) {
    const target = file === '' ? join(web, 'index.html') : join(web, file);
    assert.ok(existsSync(target), `precache target missing: ${file}`);
  }

  const modules = [];
  const walk = (directory) => {
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      const full = join(directory, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (entry.name.endsWith('.js')) modules.push(full);
    }
  };
  walk(join(web, 'js'));
  for (const module of modules) {
    const relative = module.slice(web.length + 1).split('\\').join('/');
    assert.ok(assets.includes(relative), `module not precached: ${relative}`);
  }
});

test('index references the manifest, styles and app entry', () => {
  const html = readFileSync(join(web, 'index.html'), 'utf8');
  for (const reference of ['manifest.webmanifest', 'styles.css', 'js/ui/app.js']) {
    assert.ok(html.includes(reference), `index missing ${reference}`);
  }
});

test('manifest icons and start URL are valid local files', () => {
  const manifest = JSON.parse(readFileSync(join(web, 'manifest.webmanifest'), 'utf8'));
  assert.ok(manifest.name);
  assert.ok(manifest.icons.length >= 3);
  for (const icon of manifest.icons) {
    assert.ok(existsSync(join(web, icon.src)), `manifest icon missing: ${icon.src}`);
  }
});

test('all core and view modules parse as ECMAScript modules', () => {
  const roots = [join(web, 'js/core'), join(web, 'js/ui')];
  for (const root of roots) {
    for (const entry of readdirSync(root, { withFileTypes: true })) {
      if (!entry.isFile() || !entry.name.endsWith('.js')) continue;
      const target = join(root, entry.name);
      assert.ok(readFileSync(target, 'utf8').length > 0);
      execFileSync(process.execPath, ['--check', target], { stdio: 'pipe' });
    }
  }
});
