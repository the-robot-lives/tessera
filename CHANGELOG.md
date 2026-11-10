# Changelog

## 2026-11-10

- Repo created: README with planned architecture and naming. Hex package is `noizu_tessera` with namespace `Noizu.Tessera` because bare `tessera` is taken on hex.pm. Phase 0 bridge spike is running in the `hologram-start-app` branch `spike/tessera-bridge`.
- Phase 1b: `@noizu/tessera-core` JS core npm package in `priv/js/` (defineOnce, emit + deep case conversion, globalThis-singleton event bridge with tolerant `parseTsrOn`, TesseraElement mixin over HTMLElement/LitElement, behaviors registry, BusClient seam with §5 envelope), WTR suite in `js/` (62 tests, headless), `docs/EXTENDING.md`. No runtime deps; lit optional peer; registry npm.noizu.com.
