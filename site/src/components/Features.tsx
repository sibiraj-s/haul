import type { ComponentType } from 'react'
import { ConnectionsIcon, LaptopIcon, MenuBarIcon, PauseIcon, QueueIcon, ScheduleIcon } from './Icons'

const features: { Icon: ComponentType<{ className?: string }>; title: string; body: string }[] = [
  {
    Icon: ConnectionsIcon,
    title: 'Multi-connection speed',
    body: 'Up to 16 connections per file. Big downloads finish much faster.',
  },
  {
    Icon: PauseIcon,
    title: 'Pause and resume',
    body: 'Pick up right where you left off, even after a restart or a dropped connection. Expired link? Swap in a fresh one.',
  },
  {
    Icon: QueueIcon,
    title: 'A queue that runs itself',
    body: 'Queue up downloads and Haul works through them in order, as many at a time as you like.',
  },
  {
    Icon: MenuBarIcon,
    title: 'Lives in the menu bar',
    body: 'Live speed and progress at a glance. Manage everything without opening a window.',
  },
  {
    Icon: ScheduleIcon,
    title: 'Speed limits and schedules',
    body: 'Cap your bandwidth, run big files overnight, and pause automatically on Personal Hotspot.',
  },
  {
    Icon: LaptopIcon,
    title: 'A native Mac app',
    body: 'Built with SwiftUI. Notifications, Dock progress, smart folders, duplicate detection and checksums.',
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
