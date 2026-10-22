// Release CI: publishes the Chrome and Firefox extension with Haul's v<version> release, when
// BrowserExtension/ changed since the previous release; otherwise the stores keep the version
// they have, since every upload goes through their review again. Attaches both packages to the
// GitHub release and submits them to each store whose credentials are set.
//
//   node scripts/release/extension.mjs 1.4.0
//
// Environment:
//   GH_TOKEN                attaches the packages to the release
//   CHROME_PUBLISHER_ID     Chrome Web Store: the publisher ID (Dashboard → Settings) and an
//   CHROME_ACCESS_TOKEN     access token for the chromewebstore scope, from the publisher's
//                           service account (release.yml signs in as it, with no stored key)
//   AMO_JWT_ISSUER          addons.mozilla.org API key
//   AMO_JWT_SECRET

import { execFileSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

process.chdir(join(import.meta.dirname, '../..'))
const version = process.argv[2]
if (!version) throw new Error('usage: node scripts/release/extension.mjs <version>')

const run = (command, args) => execFileSync(command, args, { encoding: 'utf8' }).trim()

// The release before this one, by tag; with none, this is the extension's first release.
function previousRelease() {
  try {
    return run('git', ['describe', '--tags', '--abbrev=0', '--match', 'v*', `v${version}^`])
  } catch {
    return null
  }
}

const previous = previousRelease()
if (previous && run('git', ['diff', '--name-only', previous, `v${version}`, '--', 'BrowserExtension']) === '') {
  console.log(`BrowserExtension/ is unchanged since ${previous}; not publishing the extension.`)
  process.exit(0)
}

run('node', ['scripts/extension.mjs'])
const chromeZip = `build/haul-chrome-${version}.zip`
const firefoxZip = `build/haul-firefox-${version}.zip`
run('gh', ['release', 'upload', `v${version}`, chromeZip, firefoxZip, '--clobber'])
console.log(`Attached ${chromeZip} and ${firefoxZip} to v${version}.`)

const missing = (names) => names.filter((name) => !process.env[name])
let failed = false

async function publishChrome() {
  const names = ['CHROME_PUBLISHER_ID', 'CHROME_ACCESS_TOKEN']
  if (missing(names).length) return console.log(`Chrome Web Store: skipped, ${missing(names).join(', ')} not set.`)
  const env = process.env

  // The item's ID comes from the key in the manifest, as in Haul's "Chrome Extension ID" build phase.
  const { key } = JSON.parse(readFileSync('BrowserExtension/manifest.json', 'utf8'))
  const hex = createHash('sha256').update(Buffer.from(key, 'base64')).digest('hex').slice(0, 32)
  const id = [...hex].map((digit) => String.fromCharCode(97 + parseInt(digit, 16))).join('')

  const headers = { Authorization: `Bearer ${env.CHROME_ACCESS_TOKEN}` }
  const item = `https://chromewebstore.googleapis.com/v2/publishers/${env.CHROME_PUBLISHER_ID}/items/${id}`
  const upload = `https://chromewebstore.googleapis.com/upload/v2/publishers/${env.CHROME_PUBLISHER_ID}/items/${id}`

  // Large uploads finish asynchronously; fetchStatus reports them as lastAsyncUploadState. The
  // API's docs spell the in-progress state both ways.
  const inProgress = (state) => state === 'IN_PROGRESS' || state === 'UPLOAD_IN_PROGRESS'
  const uploaded = await json(fetch(`${upload}:upload`, { method: 'POST', headers, body: readFileSync(chromeZip) }))
  let state = uploaded.uploadState
  for (let tries = 0; inProgress(state) && tries < 30; tries++) {
    await new Promise((resolve) => setTimeout(resolve, 10_000))
    state = (await json(fetch(`${item}:fetchStatus`, { headers }))).lastAsyncUploadState
  }
  if (state !== 'SUCCEEDED') throw new Error(`upload ended in ${state}: ${JSON.stringify(uploaded)}`)
  await json(fetch(`${item}:publish`, { method: 'POST', headers }))
  console.log(`Chrome Web Store: submitted ${version} for review.`)
}

function publishFirefox() {
  const names = ['AMO_JWT_ISSUER', 'AMO_JWT_SECRET']
  if (missing(names).length) return console.log(`Firefox Add-ons: skipped, ${missing(names).join(', ')} not set.`)
  // Submits the listed version without waiting for review; Mozilla emails the result.
  execFileSync(
    'npx',
    [
      'web-ext',
      'sign',
      '--channel=listed',
      '--source-dir=build/extension/firefox',
      '--artifacts-dir=build/web-ext',
      '--approval-timeout=0',
      `--api-key=${process.env.AMO_JWT_ISSUER}`,
      `--api-secret=${process.env.AMO_JWT_SECRET}`,
    ],
    { stdio: 'inherit' },
  )
  console.log(`Firefox Add-ons: submitted ${version} for review.`)
}

// The response's JSON, or an error with its body when the request failed.
async function json(response) {
  const res = await response
  const text = await res.text()
  if (!res.ok) throw new Error(`${res.status} ${res.url}: ${text}`)
  return text ? JSON.parse(text) : {}
}

// Each store on its own, so one failing doesn't stop the other; the job still fails after.
for (const [store, publish] of [
  ['Chrome Web Store', publishChrome],
  ['Firefox Add-ons', publishFirefox],
]) {
  try {
    await publish()
  } catch (error) {
    failed = true
    console.error(`${store}: ${error.message}`)
  }
}
if (failed) process.exit(1)
