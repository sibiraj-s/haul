import { links } from '../links'
import { useLatestRelease } from '../useLatestRelease'
import { DownloadIcon } from './Icons'

export function Hero() {
  const { version, downloadURL } = useLatestRelease()

  return (
    <section id="top" className="mx-auto flex max-w-270 flex-col items-center gap-5.5 px-6 pt-22 text-center">
      <div className="flex size-22 items-center justify-center rounded-[21px] bg-accent shadow-[inset_0_1px_0_rgba(255,255,255,.35),inset_0_0_0_.5px_rgba(0,0,0,.15),0_8px_24px_rgba(0,0,0,.18)]">
        <DownloadIcon className="size-13 stroke-white stroke-[2.2]" />
      </div>
      <h1 className="font-display text-[clamp(40px,7vw,72px)] leading-[1.04] font-bold tracking-[-.035em] text-balance">
        Downloads, handled.
      </h1>
      <p className="max-w-140 text-[clamp(17px,2vw,21px)] leading-[1.45] text-pretty text-text2">
        Haul is a download manager built for macOS.
      </p>
      <div className="flex flex-col items-center gap-2.5 pt-1.5">
        {/* The header's Download link targets this button; the scroll margin stops it mid-screen
            instead of tucked under the sticky header, with the demo filling the view. */}
        <a
          id="download"
          href={downloadURL}
          className="flex h-11.5 scroll-mt-[40vh] outline-offset-4 items-center gap-2 rounded-full bg-accent px-6.5 text-base font-semibold text-white hover:brightness-110"
        >
          <DownloadIcon className="size-4.5 stroke-white stroke-[2.2]" />
          Download for Mac
        </a>
        <span className="text-[13px] text-text2">
          Free and open source · Version {version} · macOS 26 or later · Apple Silicon
        </span>
        <span className="text-[13px] text-text2">
          Haul isn't signed with a Developer ID yet.{' '}
          <a href={links.install} className="text-accent hover:underline">
            How to open it
          </a>
        </span>
      </div>
    </section>
  )
}
