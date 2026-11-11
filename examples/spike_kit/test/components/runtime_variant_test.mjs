// Shared-runtime variant proof (brief 1d step 4) — <spike-directive-demo> from
// the BUILT runtime-variant bundle, resolved through the frame's import map
// (web-test-runner.runtime.config.mjs) to the ONE shared
// dist/tessera-runtime.esm.js instance. Proves:
//   1. the shared runtime actually SERVES the directive surface (the explicit
//      re-exports survive esbuild bundling — the `export *` tree-shake trap),
//   2. the element extends the SHARED runtime's LitElement — no second lit
//      instance (a runtime bundle that inlined its own lit would fail the
//      prototype-chain identity check),
//   3. directives behave end-to-end on that shared topology (D-01/D-02/D-06
//      condensed, mirroring the conformance directives fixture),
//   4. the runtime-variant bundle's only imports are the externals — no
//      inlined directive code (fetched bundle bytes, import-specifier scan).
// Runs under nodeResolve:false — no bare imports here (inline asserts only).
import * as sharedRuntime from "../../dist/tessera-runtime.esm.js";
import "../../dist/spike-directive-demo.runtime.esm.js";

const TAG = "spike-directive-demo";

function expect(cond, msg) {
  if (!cond) throw new Error(msg ?? "assertion failed");
}
function expectEqual(actual, wanted, msg) {
  if (actual !== wanted) {
    throw new Error(`${msg ?? "assertEqual"}: ${String(actual)} !== ${String(wanted)}`);
  }
}
async function waitFor(fn, timeout = 2000) {
  const start = Date.now();
  for (;;) {
    let ok = false;
    try {
      ok = fn();
    } catch {
      ok = false;
    }
    if (ok) return;
    if (Date.now() - start > timeout) throw new Error("waitFor timed out");
    await new Promise((r) => setTimeout(r, 10));
  }
}
function mount(attrs = {}) {
  const el = document.createElement(TAG);
  for (const [name, value] of Object.entries(attrs)) el.setAttribute(name, value);
  document.body.appendChild(el);
  return el;
}
const cy = (el, name) => el.shadowRoot.querySelector(`[data-cy=${name}]`);

describe("shared-runtime variant (spike-directive-demo + tessera-runtime.esm.js)", () => {
  it("shared runtime serves the directive surface (explicit re-exports survive bundling)", () => {
    expectEqual(typeof sharedRuntime.classMap, "function", "classMap export");
    expectEqual(typeof sharedRuntime.styleMap, "function", "styleMap export");
    expectEqual(typeof sharedRuntime.ifDefined, "function", "ifDefined export");
    expect(sharedRuntime.nothing !== undefined && sharedRuntime.nothing !== null, "nothing sentinel exported");
    expectEqual(typeof sharedRuntime.html, "function", "html export");
    expectEqual(typeof sharedRuntime.LitElement, "function", "LitElement export");
  });

  it("registers the element against the shared runtime (single lit instance)", () => {
    const ctor = customElements.get(TAG);
    expectEqual(typeof ctor, "function", "customElements registration");
    // Walk the prototype chain: it must bottom out at the SHARED runtime's
    // LitElement. An inlined second lit copy in the bundle would produce a
    // different base class and this identity check would fail.
    let proto = ctor;
    while (proto && proto !== sharedRuntime.LitElement) proto = Object.getPrototypeOf(proto);
    expectEqual(proto, sharedRuntime.LitElement, "element must extend the shared runtime's LitElement");
  });

  it("directives behave end-to-end on the shared topology (D-01/D-02/D-06/T-06)", async () => {
    const el = mount();
    await waitFor(() => el.shadowRoot !== null);
    const classNode = cy(el, "spike-dir-class");
    const styleNode = cy(el, "spike-dir-style");
    const definedNode = cy(el, "spike-dir-defined");
    const nothingAttrNode = cy(el, "spike-dir-nothing-attr");
    const nothingChildNode = cy(el, "spike-dir-nothing-child");

    // D-06 — ifDefined removes the attribute while undefined, sets it when defined.
    expect(definedNode.hasAttribute("title") === false, "ifDefined removes title when undefined");
    el.setAttribute("title-text", "hello");
    await waitFor(() => definedNode.getAttribute("title") === "hello");
    el.removeAttribute("title-text");
    await waitFor(() => !definedNode.hasAttribute("title"));

    // D-02 — styleMap sets the inline style and the custom property.
    expectEqual(styleNode.style.backgroundColor, "red", "styleMap backgroundColor");
    expectEqual(styleNode.style.getPropertyValue("--spike-directive-demo-accent").trim(), "blue", "styleMap custom property");
    el.setAttribute("bg", "green");
    await waitFor(() => styleNode.style.backgroundColor === "green");

    // T-06 — nothing: no CONTENT nodes in child position (lit-html keeps a
    // comment marker for the child part itself — nodeType 8), no attribute.
    expectEqual(nothingChildNode.textContent, "", "nothing renders no text content");
    expectEqual(nothingChildNode.children.length, 0, "nothing renders no element children");
    expect(
      [...nothingChildNode.childNodes].every((n) => n.nodeType === 8),
      "only the lit child-part comment marker remains",
    );
    expect(nothingAttrNode.hasAttribute("title") === false, "nothing removes the attribute");

    // D-01 — classMap toggles classes on action clicks.
    expect(classNode.classList.contains("active") === false, "active starts unset");
    cy(el, "spike-dir-toggle-active").click();
    await waitFor(() => classNode.classList.contains("active"));
    cy(el, "spike-dir-toggle-highlight").click();
    await waitFor(() => classNode.classList.contains("highlight"));
    expect(classNode.classList.contains("active") === true, "classes compose");
    cy(el, "spike-dir-toggle-active").click();
    await waitFor(() => !classNode.classList.contains("active"));
    expect(classNode.classList.contains("highlight") === true, "classMap removes just the toggled class");

    el.remove();
  });

  it("runtime-variant bundle carries no inlined lit/directive code (import-specifier scan)", async () => {
    const rt = await (await fetch("/dist/spike-directive-demo.runtime.esm.js")).text();
    const specs = [...rt.matchAll(/import\s*(?:[\s\S]*?from\s*)?["']([^"']+)["']/g)].map((m) => m[1]);
    const allowed = [
      "lit",
      "lit/directives/class-map.js",
      "lit/directives/style-map.js",
      "lit/directives/if-defined.js",
      "@noizu/tessera-core",
    ];
    const unexpected = specs.filter((s) => !allowed.includes(s));
    expectEqual(JSON.stringify(unexpected), "[]", "runtime bundle must import ONLY the externals");
    // every directive subpath the generated element uses stays external —
    // served by the import map, never duplicated into the bundle
    expect(specs.includes("lit/directives/class-map.js"), "class-map stays external");
    expect(specs.includes("lit/directives/style-map.js"), "style-map stays external");
    expect(specs.includes("lit/directives/if-defined.js"), "if-defined stays external");
  });
});
