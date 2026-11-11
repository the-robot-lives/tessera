# Consuming noizu_tessera in a Hologram app

Setup for host applications. Component authoring is `docs/AUTHORING.md`; the
normative wire contract is `docs/CONTRACT.md`.

## 1. Dependency

```elixir
# mix.exs
defp deps do
  [
    {:hologram, "~> 0.10"},
    {:noizu_tessera, "~> 0.1"}
  ]
end
```

`noizu_tessera` keeps `hologram` as an optional runtime:false dependency, so
non-Hologram hosts (plain Elixir + npm consumers of the generated contracts)
depend on it without pulling the framework.

## 2. Install the JS side

Add the dependency yourself first (§1 above — `mix tessera.install` does NOT
edit `mix.exs`), then run:

```sh
mix tessera.install
```

- wires `@noizu/tessera-core` into `assets/package.json` (`file:` link into
  the installed dependency's `priv/js`, always a relocatable RELATIVE path —
  including when the dep lives outside the app tree — plus lit `^3` as a
  peer; existing keys are never overwritten; re-runs are idempotent;
  dependencies that ship their own tessera `priv/js` runtime get `file:`
  entries too);
- runs `npm install` unless you pass `--no-npm`; npm missing from PATH fails
  with install guidance instead of a raw error.

Hosts that manage their own JS packaging can skip the npm leg and add
`@noizu/tessera-core` from their registry of choice themselves.

## 3. Declare components

Author components per `docs/AUTHORING.md`. Compile — the contracts,
`__tessera_spec__`, and (in Hologram) the render/bridge glue are generated at
compile time; nothing to run by hand.

## 4. Aggregate manifests

```elixir
defmodule MyApp.Tessera do
  use Noizu.Tessera.Package, components: [MyApp.Components.PersonaCard, ...]
end
```

```sh
mix tessera.manifest
```

writes `tessera-manifest.json` (full specs) and `custom-elements.json`
(Custom Elements Manifest, schemaVersion "1.0.0") into the current directory —
commit them where your tooling or downstream consumers expect.

## 5. Runtime model (what the wiring does)

- **Server render:** tessera components render as their tag with kebab-case
  attributes; boolean attrs render by presence (`false`/`nil` drop the
  attribute); json props ship as `tsr-props` (camelCase keys, HTML-encoded in
  the served HTML, decoded by the DOM); bound events render as
  `data-tsr-on="event:action@target"`.
- **Registration:** the top-level `register()` call at the end of each
  component's `.mjs` is load-bearing — stateless SSR never calls `init/3`, so
  the element gets defined only when the page bundle evaluates the `.mjs` and
  reaches that statement. The `.mjs` itself is bundled because the generated
  `init/2`/`init/3` pair calls its `register` export through an absolute-path
  `js_import` binding, keeping it on the page call graph. `mix compile` warns
  if a component's `.mjs` is missing the top-level call. Stateful instances
  additionally register through those inits. `defineOnce` in
  `@noizu/tessera-core` makes duplicate registration (multiple bundles)
  warn-once instead of throwing.
- **Events:** element → Elixir actions flow through the bridge described in
  CONTRACT.md §4. Bind an action atom (`on_persona_select={:chose}`) or a
  tuple with an explicit target (`{:chose, target: "layout"}` or
  `{:chose, target: cid}` — CONTRACT.md §3 supports cid targets only through
  the tuple form; bare binaries are rejected with an ArgumentError). With NO
  binding (`nil`/`false`, or none passed) NO `data-tsr-on` entry is rendered
  for that event and NOTHING dispatches when the element emits it — the
  event is then just a plain composed DOM `CustomEvent` that only plain
  `addEventListener` consumers see. There is no implicit default action.

## 6. Versioning note

The Elixir package and `@noizu/tessera-core` version in lockstep (0.1.x) —
the wire contract (v1) is what they share, so minor mismatches are tolerable,
but keep them in the same major.
