// WTR-only seed (brief 2f) — MUST be the first import in the Tier-1 harness:
// ES module evaluation is depth-first in import order, so this runs BEFORE
// any generated fixture module's tail. Tags listed here skip that tail's
// import-time auto-register (the emitted `if (!includes(tag)) register();`
// guard), letting defineFixtures() own the tag with a DIFFERENT class:
// <tsr-conf-form> is mounted through ConfFormRecording (the documented §6.7
// push-per-render seam), and the bare generated class winning the registry
// race silently strips the seam (the FM-02/03 FormData bug).
// The exported register() on every generated module stays available for
// explicit registration; the takeover chain (§5.9) is NOT listed — its
// import-time composition is load-bearing.
globalThis.__tesseraNoAutoRegister = ["tsr-conf-form"];
