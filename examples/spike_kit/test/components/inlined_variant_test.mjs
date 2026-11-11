// Inlined-bundle proof — <spike-directive-demo> from the BUILT self-contained
// bundle (dist/spike-directive-demo.esm.js: lit + core + directives INLINED).
// Runs in its own WTR page (fresh frame per test file), so the tag
// registration never collides with the shared-runtime lane's.
// The import map in the frame is irrelevant here: the bundle has no bare
// imports left (its import-specifier scan below asserts exactly that).
import "../../dist/spike-directive-demo.esm.js";

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
const cy = (el, name) => el.shadowRoot.querySelector(`[data-cy=${name}]`);

describe("inlined variant (spike-directive-demo.esm.js, self-contained)", () => {
  it("registers and behaves standalone (D-01/D-06 condensed)", async () => {
    expectEqual(typeof customElements.get(TAG), "function", "customElements registration");
    const el = document.createElement(TAG);
    document.body.appendChild(el);
    await waitFor(() => el.shadowRoot !== null);

    const classNode = cy(el, "spike-dir-class");
    const definedNode = cy(el, "spike-dir-defined");
    expect(definedNode.hasAttribute("title") === false, "ifDefined removes title when undefined");
    el.setAttribute("title-text", "hi");
    await waitFor(() => definedNode.getAttribute("title") === "hi");
    cy(el, "spike-dir-toggle-active").click();
    await waitFor(() => classNode.classList.contains("active"));
    el.remove();
  });

  it("inlined bundle is fully self-contained (no lit imports at all)", async () => {
    const src = await (await fetch("/dist/spike-directive-demo.esm.js")).text();
    const specs = [...src.matchAll(/import\s*(?:[\s\S]*?from\s*)?["']([^"']+)["']/g)].map((m) => m[1]);
    const litSpecs = specs.filter((s) => s === "lit" || s.startsWith("lit/"));
    expectEqual(JSON.stringify(litSpecs), "[]", "inlined bundle must have zero lit specifiers");
  });
});
