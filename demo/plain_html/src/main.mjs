// Plain-HTML demo entry: importing the component modules is ALL the setup
// they need outside Hologram — each `.mjs` has a load-bearing top-level
// `register()` call, so these imports define the custom elements. esbuild
// resolves the bare `@noizu/tessera-core` specifier (npm dependency) and the
// relative imports into the persona_kit checkout into one self-contained
// bundle (dist/bundle.js).
import "../../../examples/persona_kit/lib/persona_kit/persona_card.mjs";
import "../../../examples/persona_kit/lib/persona_kit/persona_picker.mjs";

// Vanilla consumers: tessera events are ordinary bubbling composed
// CustomEvents — plain addEventListener is the whole integration story.
const log = (name, detail) => {
  const line = document.createElement("div");
  line.setAttribute("data-cy", "plain-log-line");
  line.textContent = `${name} → ${JSON.stringify(detail)}`;
  document.getElementById("event-log").appendChild(line);
};

document.addEventListener("persona-select", (event) => {
  log("persona-select", event.detail);
});

document.addEventListener("persona-picked", (event) => {
  log("persona-picked", event.detail);
});
