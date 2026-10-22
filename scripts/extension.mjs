// Packages the Chrome and Firefox extension (BrowserExtension/) for the stores:
//
//   build/extension/chrome/     build/haul-chrome-<version>.zip    Chrome Web Store
//   build/extension/firefox/    build/haul-firefox-<version>.zip   addons.mozilla.org
//
// The extension takes Haul's version (package.json), so each one matches the release it was
// built from; the version in BrowserExtension/manifest.json only shows when it's loaded
// unpacked. BrowserExtension/ itself loads in both browsers as it is; each package drops what
// only the other browser uses.
//
//   npm run extension

import { execFileSync } from 'node:child_process'
import { copyFileSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'

process.chdir(join(import.meta.dirname, '..'))
const source = 'BrowserExtension'
const { version } = JSON.parse(readFileSync('package.json', 'utf8'))
const manifest = { ...JSON.parse(readFileSync(join(source, 'manifest.json'), 'utf8')), version }
const files = readdirSync(source).filter((file) => file === 'background.js' || file.endsWith('.png'))

const packages = {
  // Keeps `key`: the Web Store accepts its own. The webRequest permissions are only for Firefox,
  // to take downloads before its own dialog.
  chrome: ({ browser_specific_settings, background: { scripts, ...background }, ...rest }) => ({
    ...rest,
    background,
    permissions: rest.permissions.filter((permission) => !permission.startsWith('webRequest')),
  }),
  firefox: ({ key, background: { service_worker, ...background }, ...rest }) => ({ ...rest, background }),
}

rmSync('build/extension', { recursive: true, force: true })
for (const [browser, prepare] of Object.entries(packages)) {
  const dir = join('build/extension', browser)
  mkdirSync(dir, { recursive: true })
  for (const file of files) copyFileSync(join(source, file), join(dir, file))
  writeFileSync(join(dir, 'manifest.json'), JSON.stringify(prepare(manifest), null, 2) + '\n')

  const zip = `build/haul-${browser}-${version}.zip`
  rmSync(zip, { force: true })
  // From inside the folder, so manifest.json is at the zip's root as the stores require.
  execFileSync('zip', ['-qrX', join('..', '..', `haul-${browser}-${version}.zip`), '.'], { cwd: dir })
  console.log(zip)
}
