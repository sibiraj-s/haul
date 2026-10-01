import { HaulDemo } from '../demo/HaulDemo'

export function Demo() {
  return (
    <section className="mx-auto max-w-295 px-6 pt-16">
      <div className="relative aspect-16/10 w-full overflow-hidden rounded-[14px] shadow-[0_30px_80px_rgba(0,0,0,.22),0_0_0_.5px_rgba(0,0,0,.18)]">
        <HaulDemo />
      </div>
      <p className="mt-3.5 text-center text-[13px] text-text2">
        This is a live demo. Click around, use the + button to add a download, or press Space to pause.
      </p>
    </section>
  )
}
