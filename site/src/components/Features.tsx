import type { ComponentType } from 'react'
import { BellIcon, ConnectionsIcon, MenuBarIcon, PauseIcon, QueueIcon, ScheduleIcon } from './Icons'

const features: { Icon: ComponentType<{ className?: string }>; title: string; body: string }[] = [
  {
    Icon: ConnectionsIcon,
    title: 'Multi-connection speed',
    body: 'Large files are split across several connections at once, so they finish faster.',
  },
  {
    Icon: PauseIcon,
    title: 'Pause and resume',
    body: 'Stop any download and pick it up later, even after a relaunch or a dropped connection. Expired links can be swapped for fresh ones.',
  },
  {
    Icon: QueueIcon,
    title: 'A queue that runs itself',
    body: 'Set how many files download at once and reorder the rest. When one finishes, the next one starts.',
  },
  {
    Icon: MenuBarIcon,
    title: 'Lives in the menu bar',
    body: 'See live speed and progress at a glance, and manage downloads without opening the window.',
  },
  {
    Icon: ScheduleIcon,
    title: 'Speed limits and schedules',
    body: 'Cap bandwidth, let large files run overnight, and pause automatically on Personal Hotspot.',
  },
  {
    Icon: BellIcon,
    title: 'Feels like a Mac app',
    body: 'Native notifications, Dock progress, folders sorted by kind, duplicate detection and SHA-256 checksums.',
  },
]

export function Features() {
  return (
    <section id="features" className="mx-auto flex max-w-270 flex-col gap-12 px-6 pt-30">
      <h2 className="text-center font-display text-[clamp(30px,4.4vw,44px)] leading-[1.1] font-bold tracking-[-.03em] text-balance">
        Everything a download needs.
        <br />
        <span className="text-text2">Nothing it doesn't.</span>
      </h2>
      <div className="grid grid-cols-[repeat(auto-fit,minmax(min(100%,300px),1fr))] gap-px overflow-hidden rounded-[18px] border-[.5px] border-sep bg-sep">
        {features.map(({ Icon, title, body }) => (
          <div key={title} className="flex flex-col gap-2.5 bg-card p-7">
            <Icon className="size-6.5 stroke-accent stroke-[1.8]" />
            <h3 className="text-[17px] font-semibold">{title}</h3>
            <p className="text-[15px] leading-normal text-pretty text-text2">{body}</p>
          </div>
        ))}
      </div>
    </section>
  )
}
