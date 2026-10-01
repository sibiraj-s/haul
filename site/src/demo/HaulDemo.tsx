import { useEffect, useRef, useState } from 'react'
import { AppMenu, Dock, MenuBar, MenuBarPopover, Notifications, RemoveAlert } from './Desktop'
import { MainWindow, visibleRows } from './MainWindow'
import { ACCENTS } from './model'
import { SettingsWindow } from './SettingsWindow'
import { useDemo } from './useDemo'

const WIDTH = 1440
const HEIGHT = 900

function useSystemDark() {
  const [dark, setDark] = useState(() => matchMedia('(prefers-color-scheme: dark)').matches)
  useEffect(() => {
    const mq = matchMedia('(prefers-color-scheme: dark)')
    const onChange = () => setDark(mq.matches)
    mq.addEventListener('change', onChange)
    return () => mq.removeEventListener('change', onChange)
  }, [])
  return dark
}

/// An interactive mock of Haul on a macOS desktop, scaled to fit its container.
export function HaulDemo() {
  const demo = useDemo()
  const { state, update } = demo
  const stage = useRef<HTMLDivElement>(null)
  const [scale, setScale] = useState(0)
  const systemDark = useSystemDark()

  useEffect(() => {
    const el = stage.current
    if (!el) return
    const observer = new ResizeObserver(([entry]) => {
      const { width, height } = entry.contentRect
      setScale(Math.min(width / WIDTH, height / HEIGHT))
    })
    observer.observe(el)
    return () => observer.disconnect()
  }, [])

  const { appearance, accent } = state.settings
  const theme = appearance === 'auto' ? (systemDark ? 'dark' : 'light') : appearance

  const onKeyDown = (e: React.KeyboardEvent) => {
    const typing = (e.target as HTMLElement).tagName === 'INPUT' || (e.target as HTMLElement).tagName === 'SELECT'
    const key = e.key.toLowerCase()
    if (e.key === 'Escape') return update(() => ({ addOpen: false, menu: null, confirmRemove: null }))
    if (e.metaKey && key === 'n') {
      e.preventDefault()
      return demo.openAdd()
    }
    if (e.metaKey && key === ',') {
      e.preventDefault()
      return demo.openSettings()
    }
    if (e.metaKey && key === '0') {
      e.preventDefault()
      return update(() => ({ winOpen: true, front: 'main' }))
    }
    if (e.metaKey && e.altKey && e.code === 'KeyP') {
      e.preventDefault()
      return demo.pauseAll()
    }
    if (e.metaKey && e.altKey && e.code === 'KeyR') {
      e.preventDefault()
      return demo.resumeAll()
    }
    if (e.key === 'Enter' && state.addOpen) return demo.confirmAdd()
    if (typing || state.addOpen || !state.winOpen) return

    const rows = visibleRows(demo)
    const i = rows.findIndex((d) => d.id === state.sel)
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault()
      const next = rows[e.key === 'ArrowDown' ? Math.min(rows.length - 1, i + 1) : Math.max(0, i - 1)]
      if (next) update(() => ({ sel: next.id }))
    }
    if (e.key === ' ' && state.sel !== null) {
      e.preventDefault()
      demo.toggle(state.sel)
    }
    if (e.key === 'Backspace' && e.metaKey && state.sel !== null) demo.requestRemove(state.sel)
  }

  return (
    <div ref={stage} className="relative size-full overflow-hidden bg-[#111]">
      <div
        tabIndex={0}
        onKeyDown={onKeyDown}
        data-theme={theme}
        className="hd absolute top-1/2 left-1/2 overflow-hidden font-sans text-[13px] leading-normal text-text outline-none select-none"
        style={{
          width: WIDTH,
          height: HEIGHT,
          transform: `translate(-50%, -50%) scale(${scale})`,
          ['--accent' as string]: ACCENTS[accent],
        }}
      >
        <MenuBar demo={demo} />
        {state.winOpen && <MainWindow demo={demo} />}
        {state.settingsOpen && <SettingsWindow demo={demo} />}
        {state.menu && <div className="absolute inset-0 z-48" onMouseDown={() => update(() => ({ menu: null }))} />}
        {state.menu === 'app' && <AppMenu demo={demo} />}
        {state.menu === 'extra' && state.settings.menuBar && <MenuBarPopover demo={demo} />}
        <RemoveAlert demo={demo} />
        <Notifications demo={demo} />
        <Dock demo={demo} />
      </div>
    </div>
  )
}
