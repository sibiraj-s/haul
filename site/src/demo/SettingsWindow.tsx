import { version } from '../../../package.json'
import { links } from '../links'
import { AppTile, cx, Glyph, Group, ICON, Pill, PopUp, Row, Segmented, Switch } from './controls'
import { ACCENTS, hourLabel, LIST_CLEANUP, MAX_RETRIES, type Accent, type Appearance } from './model'
import type { Demo, Pane } from './useDemo'

const PANES: [Pane, string, string][] = [
  ['general', 'General', ICON.gear],
  ['downloads', 'Downloads', ICON.download],
  ['network', 'Network', ICON.globe],
  ['notifications', 'Notifications', ICON.bell],
  ['about', 'About', ICON.info],
]

const HOURS = Array.from({ length: 24 }, (_, h) => [h, hourLabel(h)] as [number, string])

export function SettingsWindow({ demo }: { demo: Demo }) {
  const { state, update } = demo
  const title = PANES.find(([p]) => p === state.pane)![1]

  return (
    <div
      onMouseDown={() => state.front !== 'settings' && update(() => ({ front: 'settings' }))}
      className="absolute top-24 left-[calc(50%-220px)] flex w-140 flex-col overflow-hidden rounded-[18px] bg-win shadow-window"
      style={{ zIndex: state.front === 'settings' ? 12 : 10 }}
    >
      <div className="relative flex flex-col items-center border-b-[.5px] border-sep px-3 pt-2.5 pb-2">
        <div className="absolute top-3.5 left-3.5 flex gap-2">
          <button
            onClick={() => update(() => ({ settingsOpen: false }))}
            className="size-3 rounded-full bg-[#ff5f57]"
            aria-label="Close"
          />
          <span className="size-3 rounded-full bg-track" />
          <span className="size-3 rounded-full bg-track" />
        </div>
        <div className="mb-2 text-[13px] font-semibold">{title}</div>
        <div className="flex gap-1">
          {PANES.map(([pane, label, icon]) => (
            <button
              key={pane}
              onClick={() => update(() => ({ pane }))}
              className={cx(
                'flex h-12 w-19 flex-col items-center justify-center gap-0.75 rounded-[9px]',
                state.pane === pane ? 'bg-selg text-accent' : 'text-text2',
              )}
            >
              <Glyph d={icon} size={20} width={1.6} />
              <span className="text-[11px]">{label}</span>
            </button>
          ))}
        </div>
      </div>
      <div className="flex min-h-75 flex-col gap-3.5 px-5 pt-4 pb-5">
        {state.pane === 'general' && <General demo={demo} />}
        {state.pane === 'downloads' && <Downloads demo={demo} />}
        {state.pane === 'network' && <Network demo={demo} />}
        {state.pane === 'notifications' && <Notifications demo={demo} />}
        {state.pane === 'about' && <About />}
      </div>
    </div>
  )
}

/// A switch bound to one boolean setting.
function useToggle(demo: Demo) {
  return (
    key: {
      [K in keyof Demo['state']['settings']]: Demo['state']['settings'][K] extends boolean ? K : never
    }[keyof Demo['state']['settings']],
  ) => <Switch on={demo.state.settings[key]} onChange={(on) => demo.setSetting(key, on)} />
}

function General({ demo }: { demo: Demo }) {
  const { settings: s, now, checkingUntil } = demo.state
  const toggle = useToggle(demo)
  const checking = now < checkingUntil
  return (
    <>
      <Group>
        <Row title="Appearance">
          <Segmented<Appearance>
            options={[
              ['light', 'Light'],
              ['dark', 'Dark'],
              ['auto', 'Auto'],
            ]}
            value={s.appearance}
            onChange={(v) => demo.setSetting('appearance', v)}
            minWidth={56}
          />
        </Row>
        <Row title="Accent colour">
          <div className="flex gap-2">
            {(Object.keys(ACCENTS) as Accent[]).map((a) => (
              <button
                key={a}
                title={a}
                onClick={() => demo.setSetting('accent', a)}
                className="size-4 rounded-full"
                style={{
                  background: ACCENTS[a],
                  boxShadow:
                    s.accent === a
                      ? `0 0 0 2px var(--win), 0 0 0 3.5px ${ACCENTS[a]}`
                      : 'inset 0 0 0 .5px rgba(0,0,0,.2)',
                }}
              />
            ))}
          </div>
        </Row>
      </Group>
      <Group>
        <Row title="Show in menu bar" caption="Progress ring and live speed next to the clock.">
          {toggle('menuBar')}
        </Row>
        <Row title="Show progress on Dock icon">{toggle('dockProgress')}</Row>
        <Row title="Open at login">{toggle('launchAtLogin')}</Row>
      </Group>
      <Group>
        <Row title="Ask before removing downloads">{toggle('confirmRemove')}</Row>
        <Row title="Remove finished downloads from list">
          <PopUp
            options={LIST_CLEANUP}
            value={s.removeFinished}
            onChange={(v) => demo.setSetting('removeFinished', v)}
          />
        </Row>
        <Row
          title="Remove downloads whose file was deleted"
          caption="Also when the file is moved or renamed in Finder."
        >
          {toggle('removeDeleted')}
        </Row>
      </Group>
      <Group>
        <Row title="Check for updates automatically" caption="Once a day, from Haul's GitHub releases.">
          {toggle('checkForUpdates')}
        </Row>
        <Row title={`Version ${version}`}>
          <Pill
            small
            className="h-6"
            disabled={checking}
            onClick={() => demo.update(() => ({ checkingUntil: Date.now() + 1500 }))}
          >
            {checking ? 'Checking…' : 'Check Now'}
          </Pill>
        </Row>
      </Group>
    </>
  )
}

function Downloads({ demo }: { demo: Demo }) {
  const s = demo.state.settings
  const toggle = useToggle(demo)
  const stepper = (d: string, delta: number) => (
    <button
      onClick={() => demo.setSetting('maxConcurrent', Math.min(8, Math.max(1, s.maxConcurrent + delta)))}
      className="flex h-2.75 w-4 items-center justify-center"
    >
      <Glyph d={d} size={9} width={3} />
    </button>
  )
  return (
    <>
      <Group>
        <Row title="Save downloads to">
          <PopUp
            options={[
              ['Downloads', 'Downloads'],
              ['other', 'Other…'],
            ]}
            value="Downloads"
            onChange={() => {}}
            icon={<Glyph d={ICON.folder} size={14} className="text-accent" />}
          />
        </Row>
        <Row title="Sort into folders by kind" caption="Movies, Music, Pictures, Documents, Archives, Apps.">
          {toggle('autoSort')}
        </Row>
        <Row title="Compute SHA-256 checksums" caption="Shown in the inspector to compare with the publisher's.">
          {toggle('computeChecksum')}
        </Row>
        <Row title="Use the server's file date" caption="Files keep the date they last changed on the server.">
          {toggle('useServerDate')}
        </Row>
        <Row title="Record where files came from" caption="Shown as “Where from” in Finder's Get Info.">
          {toggle('recordSource')}
        </Row>
      </Group>
      <Group>
        <Row title="Simultaneous downloads">
          <div className="flex items-center gap-2.5">
            <span className="min-w-3 text-right tabular-nums">{s.maxConcurrent}</span>
            <div className="flex flex-col overflow-hidden rounded-[5px] bg-ctl shadow-ctl">
              {stepper(ICON.up, 1)}
              <div className="h-[.5px] bg-ctl-border" />
              {stepper(ICON.down, -1)}
            </div>
          </div>
        </Row>
        <Row title="Connections per download">
          <Segmented
            options={[1, 4, 8, 16].map((n) => [n, String(n)] as [number, string])}
            value={s.connections}
            onChange={(v) => demo.setSetting('connections', v)}
            minWidth={34}
          />
        </Row>
        <Row
          title="Prevent sleep while downloading"
          caption="The display can still turn off. Closing the lid still sleeps."
        >
          {toggle('preventSleep')}
        </Row>
      </Group>
    </>
  )
}

function Network({ demo }: { demo: Demo }) {
  const s = demo.state.settings
  const toggle = useToggle(demo)
  return (
    <>
      <Group>
        <Row title="Limit download speed">{toggle('limitOn')}</Row>
        <div className={cx('flex items-center gap-3 px-3 py-2.5', !s.limitOn && 'opacity-40')}>
          <span className="text-xs text-text2">1 MB/s</span>
          <input
            type="range"
            min={1}
            max={50}
            value={s.limitMBps}
            onChange={(e) => demo.setSetting('limitMBps', Number(e.target.value))}
            className="flex-1 accent-accent"
          />
          <span className="min-w-14.5 text-right text-xs font-semibold tabular-nums">{s.limitMBps} MB/s</span>
        </div>
      </Group>
      <Group>
        <Row title="Only download on a schedule" caption="Queued downloads only start during these hours.">
          {toggle('scheduleOnly')}
        </Row>
        <div className={cx('flex items-center gap-2 px-3 py-2.5', !s.scheduleOnly && 'opacity-40')}>
          <span className="text-text2">From</span>
          <PopUp options={HOURS} value={s.scheduleFrom} onChange={(v) => demo.setSetting('scheduleFrom', v)} />
          <span className="text-text2">to</span>
          <PopUp options={HOURS} value={s.scheduleTo} onChange={(v) => demo.setSetting('scheduleTo', v)} />
        </div>
        <Row title="Pause on Personal Hotspot" caption="Also respects Low Data Mode.">
          {toggle('pauseOnExpensive')}
        </Row>
      </Group>
      <Group>
        <Row
          title="Retry failed downloads"
          caption={`Up to ${MAX_RETRIES} times after a dropped connection or server error.`}
        >
          {toggle('autoRetry')}
        </Row>
        <Row title="Skip web pages" caption="Links that open an HTML page instead of a file aren't saved.">
          {toggle('skipWebPages')}
        </Row>
      </Group>
    </>
  )
}

function Notifications({ demo }: { demo: Demo }) {
  const toggle = useToggle(demo)
  return (
    <>
      <Group>
        <Row title="Download added">{toggle('notifyAdded')}</Row>
        <Row title="Download finished">{toggle('notify')}</Row>
        <Row title="Download failed" caption="After any automatic retries have run out.">
          {toggle('notifyFailed')}
        </Row>
      </Group>
      <Group>
        <Row title="Only when Haul isn't in front">{toggle('notifyOnlyInBackground')}</Row>
      </Group>
    </>
  )
}

function About() {
  return (
    <div className="flex flex-col items-center pt-3 text-center">
      <AppTile size={96} radius={22} glyph={56} />
      <div className="mt-2 text-xl font-semibold">Haul</div>
      <div className="mt-0.5 text-xs text-text2 select-text">Version {version}</div>
      <div className="mt-4.5 text-xs text-text2">Haul is free and open source. Sponsoring helps keep it that way.</div>
      <a
        href={links.sponsor}
        target="_blank"
        rel="noreferrer"
        className="mt-3 inline-flex h-7 items-center rounded-[14px] bg-accent px-4 font-medium text-white!"
      >
        ♥ Sponsor Haul
      </a>
    </div>
  )
}
