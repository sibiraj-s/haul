import { links } from '../links'
import { HeartIcon } from './Icons'

export function Sponsor() {
  return (
    <section id="sponsor" className="mx-auto max-w-270 px-6 pt-30">
      <div className="flex flex-col items-center gap-4 rounded-3xl bg-bg2 px-6 py-[clamp(36px,6vw,64px)] text-center">
        <HeartIcon className="size-9 fill-sponsor stroke-sponsor stroke-[1.7]" />
        <h2 className="font-display text-[clamp(28px,4vw,40px)] leading-[1.1] font-bold tracking-[-.03em] text-balance">
          Free, with no ads.
        </h2>
        <p className="max-w-130 text-[17px] leading-normal text-pretty text-text2">
          Haul is free and open source. Sponsorship pays for updates and keeps it independent.
        </p>
        <a
          href={links.sponsor}
          className="mt-2 flex h-10 items-center rounded-full border border-sep bg-card px-5.5 text-[15px] font-semibold text-text hover:border-text2"
        >
          Sponsor Haul
        </a>
      </div>
    </section>
  )
}
