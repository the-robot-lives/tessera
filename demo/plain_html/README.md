# Plain-HTML demo — tessera components with zero framework

`persona-card` / `persona-picker` are ordinary custom elements; consuming
them from a plain HTML page is one `<script type="module">` import and
vanilla `addEventListener`. The events are bubbling, composed
`CustomEvent`s (CONTRACT.md §4), so no bridge, no framework, no Hologram.

## Run it

```sh
cd demo/plain_html
npm install     # lit + @noizu/tessera-core (file: dep) + esbuild
npm run build   # bundles src/main.mjs → dist/bundle.js (self-contained ESM)
npm run serve   # tiny static server on http://localhost:5587
```

Then open **http://localhost:5587**. Click a card's select button or a
picker entry: the vanilla event log at the bottom prints the event detail
(`{"personaId": "...", "clickCount": n}` / `{"personaId": "..."}`) exactly
as the wire contract specifies.

`PORT=1234 npm run serve` changes the port.

> **Bundling note:** the bundle imports the component sources from
> `examples/persona_kit`, and each of those imports `"lit"`. esbuild resolves
> bare specifiers from the *importing file's* `node_modules` chain, so a
> fresh clone must also run `npm ci` (or `npm install`) once in
> `examples/persona_kit` — not just here — before `npm run build` works.
> Local checkouts usually have it already (from the persona_kit WTR suite).

## What the page does

* `src/main.mjs` imports the two component modules — each has a
  load-bearing top-level `register()` call, so the import alone defines
  `<persona-card>` / `<persona-picker>`.
* `index.html` sets attributes (`display-name`, `tag_list`) and the
  `tsr-props` JSON attribute (`personas`) exactly as documented in
  docs/CONSUMING.md.
* `document.addEventListener("persona-select" | "persona-picked", …)`
  logs `event.detail` — the entire consumer integration.

## React note

Any framework that renders DOM can host tessera elements. A minimal React
host (~10 lines) — React 19 passes `class`/custom attributes through
better than 18, but plain DOM attributes keep it simple:

```jsx
import { useEffect, useRef } from "react";
import "./persona-kit.js"; // one bundle importing the component modules

export function PersonaPicker({ onPicked }) {
  const ref = useRef(null);
  useEffect(() => {
    const el = ref.current;
    const handler = (e) => onPicked(e.detail);
    el.addEventListener("persona-picked", handler);
    return () => el.removeEventListener("persona-picked", handler);
  }, [onPicked]);
  return (
    <persona-picker
      ref={ref}
      title="Pick a persona"
      tsr-props={JSON.stringify({ personas: [{ id: "ada", name: "Ada Lovelace", tags: ["logic"] }] })}
    />
  );
}
```

The snippet is illustrative (not executed here): the only React-specific
points are refetching the element ref and addEventListener cleanup —
tessera never needs wrapper components to bridge props or events.
