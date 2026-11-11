import { expect } from "@open-wc/testing";
import { parseTsrOn, registerEvents } from "../../priv/js/src/bridge.mjs";
import { emit } from "../../priv/js/src/events.mjs";
import { captureWarns } from "./helpers.mjs";

// FAST group: the core claim — parseTsrOn grammar + shadow-event → dispatchAction
// bridge dispatch. The cross-module-copy singleton hardening lives in the FULL
// group (bridge.copies.test.mjs). docs/notes/test-tiering.md.

describe("parseTsrOn", () => {
  it("parses a single entry", () => {
    expect(parseTsrOn("persona-select:chose@page")).to.deep.equal(
      new Map([["persona-select", { action: "chose", target: "page" }]]),
    );
  });

  it("parses multiple entries", () => {
    const map = parseTsrOn("persona-select:chose@page;persona-hover:hover@picker1");
    expect(map.get("persona-select")).to.deep.equal({ action: "chose", target: "page" });
    expect(map.get("persona-hover")).to.deep.equal({ action: "hover", target: "picker1" });
    expect(map.size).to.equal(2);
  });

  it("supports a cid target and tolerates whitespace", () => {
    const map = parseTsrOn(" item-add : pushed @shopping-list-1 ");
    expect(map.get("item-add")).to.deep.equal({ action: "pushed", target: "shopping-list-1" });
  });

  it("empty or missing attribute yields an empty map without warnings", () => {
    const warns = captureWarns(() => {
      expect(parseTsrOn("")).to.deep.equal(new Map());
      expect(parseTsrOn(null)).to.deep.equal(new Map());
      expect(parseTsrOn(undefined)).to.deep.equal(new Map());
      expect(parseTsrOn(";;")).to.deep.equal(new Map());
    });
    expect(warns).to.have.lengthOf(0);
  });

  it("skips malformed entries with a console.warn and keeps the rest", () => {
    const warns = captureWarns(() => {
      const map = parseTsrOn("no-colon@page;good:action@layout;:missing-event@page;no-action:@page;trailing@");
      expect(map.size).to.equal(1);
      expect(map.get("good")).to.deep.equal({ action: "action", target: "layout" });
    });
    expect(warns.length).to.equal(4);
    for (const w of warns) expect(w).to.include("malformed data-tsr-on entry");
  });

  it("empty action / target / event are malformed", () => {
    const warns = captureWarns(() => {
      expect(parseTsrOn("evt:@page").size).to.equal(0);
      expect(parseTsrOn("evt:action@").size).to.equal(0);
      expect(parseTsrOn(":action@page").size).to.equal(0);
    });
    expect(warns.length).to.equal(3);
  });

  // Grammar characters inside VALUES. Generated markup can never carry them
  // (compile-time spec validation + render-time adapter guard), but the
  // parser's behavior for hand-written attributes is pinned here — in
  // particular WHICH `@` terminates the action (MUT-8 gap).
  it("an `@` inside the action: the LAST @ separates action from target", () => {
    const map = parseTsrOn("evt:a@b@page");
    expect(map.get("evt")).to.deep.equal({ action: "a@b", target: "page" });
  });

  it("a `:` inside the action: only the FIRST colon splits the event", () => {
    const map = parseTsrOn("evt:a:b:c@page");
    expect(map.get("evt")).to.deep.equal({ action: "a:b:c", target: "page" });
  });

  it("a `:` after the @ stays in the target (tolerant parse, compile-time guard upstream)", () => {
    const map = parseTsrOn("evt:action@page:extra");
    expect(map.get("evt")).to.deep.equal({ action: "action", target: "page:extra" });
  });

  it("a `;` inside a value terminates the entry — both halves are malformed and warned", () => {
    const warns = captureWarns(() => {
      // "evt:ac" has no @; "ion@page" has no colon. Neither may silently bind.
      expect(parseTsrOn("evt:ac;ion@page").size).to.equal(0);
    });
    expect(warns.length).to.equal(2);
    for (const w of warns) expect(w).to.include("malformed data-tsr-on entry");
  });
});

describe("bridge dispatch", () => {
  const calls = [];
  let originalHologram;

  before(() => {
    originalHologram = globalThis.Hologram;
    globalThis.Hologram = { dispatchAction: (...args) => calls.push(args) };
  });

  after(() => {
    if (originalHologram === undefined) delete globalThis.Hologram;
    else globalThis.Hologram = originalHologram;
  });

  beforeEach(() => {
    calls.length = 0;
  });

  it("delivers an event fired inside a shadow root with snake_case params and the right action/target", () => {
    registerEvents(["bridge-shadow-evt"]);
    const host = document.createElement("div");
    host.setAttribute("data-tsr-on", "bridge-shadow-evt:chose@page");
    const shadowChild = document.createElement("button");
    host.attachShadow({ mode: "open" }).appendChild(shadowChild);
    document.body.appendChild(host);

    shadowChild.dispatchEvent(
      new CustomEvent("bridge-shadow-evt", { detail: { personaId: "Ada", clickCount: 2 }, bubbles: true, composed: true }),
    );

    expect(calls).to.have.lengthOf(1);
    expect(calls[0]).to.deep.equal(["chose", "page", { persona_id: "Ada", click_count: 2 }]);
    host.remove();
  });

  it("dispatches nothing when the host has no data-tsr-on mapping", () => {
    registerEvents(["bridge-unmapped-evt"]);
    const plain = document.createElement("div");
    document.body.appendChild(plain);
    plain.dispatchEvent(new CustomEvent("bridge-unmapped-evt", { bubbles: true, composed: true, detail: { a: 1 } }));
    expect(calls).to.have.lengthOf(0);
    plain.remove();
  });

  it("dispatches nothing when the event type has no matching entry", () => {
    registerEvents(["bridge-other-evt"]);
    const host = document.createElement("div");
    host.setAttribute("data-tsr-on", "bridge-other-evt:chose@page");
    document.body.appendChild(host);
    host.dispatchEvent(new CustomEvent("bridge-other-evt-2", { bubbles: true, composed: true }));
    expect(calls).to.have.lengthOf(0);
    host.remove();
  });

  it("passes an empty object when the event carries no detail", () => {
    registerEvents(["bridge-nodetail-evt"]);
    const host = document.createElement("div");
    host.setAttribute("data-tsr-on", "bridge-nodetail-evt:touched@layout");
    document.body.appendChild(host);
    host.dispatchEvent(new CustomEvent("bridge-nodetail-evt", { bubbles: true, composed: true }));
    expect(calls).to.have.lengthOf(1);
    expect(calls[0]).to.deep.equal(["touched", "layout", {}]);
    host.remove();
  });

  it("resolves a host from composedPath when a nested element re-dispatches the event (tag registered)", () => {
    registerEvents(["bridge-nested-evt"], "bridge-nested-tag");
    const host = document.createElement("bridge-nested-tag");
    host.setAttribute("data-tsr-on", "bridge-nested-evt:add@list1");
    const child = document.createElement("button");
    child.textContent = "add";
    host.appendChild(child);
    document.body.appendChild(host);

    // No shadow boundary here: event.target is the nested child.
    child.dispatchEvent(new CustomEvent("bridge-nested-evt", { bubbles: true, composed: true, detail: { itemId: "x" } }));

    expect(calls).to.have.lengthOf(1);
    expect(calls[0]).to.deep.equal(["add", "list1", { item_id: "x" }]);
    host.remove();
  });

  it("composedPath fallback only honours REGISTERED contract tags", () => {
    registerEvents(["bridge-stray-evt"], "bridge-registered-tag");
    const stranger = document.createElement("div");
    stranger.setAttribute("data-tsr-on", "bridge-stray-evt:steal@page");
    const child = document.createElement("button");
    stranger.appendChild(child);
    document.body.appendChild(stranger);

    child.dispatchEvent(new CustomEvent("bridge-stray-evt", { bubbles: true, composed: true }));
    // The unregistered <div> mapping must NOT hijack the nested event.
    expect(calls).to.have.lengthOf(0);
    stranger.remove();
  });

  it("a registered contract host is found via composedPath past unregistered ancestors", () => {
    registerEvents(["bridge-nested2-evt"], "bridge-nested2-tag");
    const stranger = document.createElement("div");
    stranger.setAttribute("data-tsr-on", "bridge-nested2-evt:steal@page");
    const registeredHost = document.createElement("bridge-nested2-tag");
    registeredHost.setAttribute("data-tsr-on", "bridge-nested2-evt:ok@page");
    const child = document.createElement("button");
    registeredHost.appendChild(child);
    stranger.appendChild(registeredHost);
    document.body.appendChild(stranger);

    child.dispatchEvent(new CustomEvent("bridge-nested2-evt", { bubbles: true, composed: true }));
    expect(calls).to.have.lengthOf(1);
    expect(calls[0][0]).to.equal("ok", "first registered element carrying a mapping wins");
    stranger.remove();
  });

  it("does nothing (and does not throw) when globalThis.Hologram is absent", () => {
    const saved = globalThis.Hologram;
    delete globalThis.Hologram;
    try {
      registerEvents(["bridge-nohologram-evt"]);
      const host = document.createElement("div");
      host.setAttribute("data-tsr-on", "bridge-nohologram-evt:chose@page");
      document.body.appendChild(host);
      expect(() => {
        host.dispatchEvent(new CustomEvent("bridge-nohologram-evt", { bubbles: true, composed: true, detail: { a: 1 } }));
      }).to.not.throw();
      expect(calls).to.have.lengthOf(0);
      host.remove();
    } finally {
      if (saved === undefined) delete globalThis.Hologram;
      else globalThis.Hologram = saved;
    }
  });

  it("event.target (post-retarget) wins over a deeper composedPath mapping", () => {
    registerEvents(["bridge-priority-evt"], "bridge-priority-tag");
    const outer = document.createElement("bridge-priority-tag");
    outer.setAttribute("data-tsr-on", "bridge-priority-evt:outer@page");
    const inner = document.createElement("bridge-priority-tag");
    inner.setAttribute("data-tsr-on", "bridge-priority-evt:inner@layout");
    outer.appendChild(inner);
    document.body.appendChild(outer);

    inner.dispatchEvent(new CustomEvent("bridge-priority-evt", { bubbles: true, composed: true }));
    expect(calls).to.have.lengthOf(1);
    expect(calls[0][0]).to.equal("inner", "the element the event actually fired on wins");
    outer.remove();
  });

  it("a tessera element nested INSIDE another tessera element's shadow root is attributed to the OUTER host (shadow retargeting)", () => {
    registerEvents(["bridge-shadow-nested-evt"], "bridge-shadow-outer-tag");
    registerEvents(["bridge-shadow-nested-evt"], "bridge-shadow-inner-tag");

    const outer = document.createElement("bridge-shadow-outer-tag");
    outer.setAttribute("data-tsr-on", "bridge-shadow-nested-evt:outer@page");
    const inner = document.createElement("bridge-shadow-inner-tag");
    inner.setAttribute("data-tsr-on", "bridge-shadow-nested-evt:inner@layout"); // must NEVER fire
    outer.attachShadow({ mode: "open" }).appendChild(inner);
    document.body.appendChild(outer);

    emit(inner, "bridge-shadow-nested-evt", { itemId: "q" });

    expect(calls).to.have.lengthOf(1);
    expect(calls[0]).to.deep.equal(
      ["outer", "page", { item_id: "q" }],
      "the retargeted shadow host is tried first: the outer binding fires, the inner binding for the same event never does",
    );
    outer.remove();
  });

  it("when the shadow host is unmapped, the composedPath fallback finds the inner registered host (NOT a drop)", () => {
    registerEvents(["bridge-shadow-drop-evt"], "bridge-shadow-drop-tag");
    const outer = document.createElement("bridge-shadow-drop-tag"); // NO data-tsr-on
    const inner = document.createElement("bridge-shadow-drop-tag");
    inner.setAttribute("data-tsr-on", "bridge-shadow-drop-evt:inner@layout");
    outer.attachShadow({ mode: "open" }).appendChild(inner);
    document.body.appendChild(outer);

    emit(inner, "bridge-shadow-drop-evt", { itemId: "z" });

    // The retargeted target (outer) is tried FIRST and has no entry; the
    // fallback then scans the composed path — open-shadow internals are
    // visible on it — and resolves the inner registered tessera host.
    expect(calls).to.have.lengthOf(1);
    expect(calls[0]).to.deep.equal(["inner", "layout", { item_id: "z" }]);
    outer.remove();
  });

  it("drops the event when the host is unmapped and the inner element's tag is NOT registered", () => {
    registerEvents(["bridge-shadow-stray-evt"], "bridge-shadow-stray-outer-tag");
    const outer = document.createElement("bridge-shadow-stray-outer-tag"); // registered tag, NO data-tsr-on
    const inner = document.createElement("div"); // unregistered tag carrying a mapping — cannot hijack
    inner.setAttribute("data-tsr-on", "bridge-shadow-stray-evt:steal@layout");
    outer.attachShadow({ mode: "open" }).appendChild(inner);
    document.body.appendChild(outer);

    emit(inner, "bridge-shadow-stray-evt", {});

    expect(calls).to.have.lengthOf(0, "no registered element on the (retargeted) path maps the event ⇒ dropped");
    outer.remove();
  });
});
