import { expect } from "@open-wc/testing";
import {
  makeSnapshot,
  normalizeActionName,
  normalizeParams,
  runPipeline,
} from "../../priv/js/src/pipeline.mjs";

// Unit tests for the pure action pipeline (EXTENSION-CONTRACT.md §6.2–§6.4).
// pipeline.mjs is Lit/DOM-free by design (docs/notes/test-tiering.md), so the
// onion/veto/async/error/stale semantics are pinned here directly; the element
// wiring (events, commit, statics) lives in element.test.mjs and the X-family
// conformance cases.

describe("makeSnapshot (§6.2, U2/D3)", () => {
  const el = () => ({ count: 3, selected_id: "a", meta: { depth: 1 } });

  it("canonical camel keys, enumerable, declaration order", () => {
    const snap = makeSnapshot(el(), ["count", "selected_id", "meta"]);
    expect(Object.keys(snap)).to.deep.equal(["count", "selectedId", "meta"]);
    expect(snap.selectedId).to.equal("a");
  });

  it("snake aliases are non-enumerable and identical to the canonical value", () => {
    const snap = makeSnapshot(el(), ["count", "selected_id", "meta"]);
    expect(snap.selected_id).to.equal(snap.selectedId);
    const d = Object.getOwnPropertyDescriptor(snap, "selected_id");
    expect(d.enumerable).to.equal(false);
    // keys that round-trip to themselves (count) get NO alias property beyond
    // the canonical one
    expect(Object.prototype.hasOwnProperty.call(snap, "count")).to.equal(true);
    expect(Object.getOwnPropertyNames(snap)).to.have.members([
      "count", "selectedId", "meta", "selected_id",
    ]);
  });

  it("frozen at the TOP LEVEL only; nested values shared by reference", () => {
    const src = el();
    const snap = makeSnapshot(src, ["count", "selected_id", "meta"]);
    expect(Object.isFrozen(snap)).to.equal(true);
    expect(Object.isFrozen(snap.meta)).to.equal(false);
    expect(snap.meta).to.equal(src.meta);
    expect(() => { snap.count = 99; }).to.throw();
  });

  it("fresh object per call; JSON/spread see camelCase only", () => {
    const a = makeSnapshot(el(), ["count", "selected_id"]);
    const b = makeSnapshot(el(), ["count", "selected_id"]);
    expect(a).to.not.equal(b);
    expect(a).to.deep.equal(b);
    expect(JSON.parse(JSON.stringify(a)).selected_id).to.equal(undefined);
  });

  it("no state keys ⇒ frozen empty object", () => {
    const snap = makeSnapshot({}, []);
    expect(Object.keys(snap)).to.deep.equal([]);
    expect(Object.isFrozen(snap)).to.equal(true);
  });
});

describe("normalizeActionName (D3)", () => {
  it("either casing normalizes to the snake canonical", () => {
    expect(normalizeActionName("select_item")).to.equal("select_item");
    expect(normalizeActionName("selectItem")).to.equal("select_item");
    expect(normalizeActionName("bump")).to.equal("bump");
  });
  it("non-string / empty ⇒ null (unknown-action path)", () => {
    expect(normalizeActionName(42)).to.equal(null);
    expect(normalizeActionName(null)).to.equal(null);
    expect(normalizeActionName("")).to.equal(null);
  });
});

describe("normalizeParams (D3, §6.3)", () => {
  it("undefined/null ⇒ {}", () => {
    expect(normalizeParams(undefined)).to.deep.equal({ ok: true, snake: {} });
    expect(normalizeParams(null)).to.deep.equal({ ok: true, snake: {} });
  });

  it("camelCase keys convert deep to snake_case", () => {
    const { ok, snake } = normalizeParams({ itemName: "x", nested: { maxScore: 9 } });
    expect(ok).to.equal(true);
    expect(snake).to.deep.equal({ item_name: "x", nested: { max_score: 9 } });
  });

  it("top-level `_`-prefixed keys are STRIPPED with a warn", () => {
    const warns = [];
    const { ok, snake } = normalizeParams({ _secret: 1, step: 2 }, (m) => warns.push(String(m)));
    expect(ok).to.equal(true);
    expect(snake).to.deep.equal({ step: 2 });
    expect(warns.length).to.equal(1);
    expect(warns[0]).to.include("_secret");
  });

  it("function values ANYWHERE are rejected", () => {
    expect(normalizeParams({ fn: () => {} }).ok).to.equal(false);
    expect(normalizeParams({ nested: { fn: () => {} } }).ok).to.equal(false);
    expect(normalizeParams([() => {}]).ok).to.equal(false); // arrays rejected too
    const warns = [];
    expect(normalizeParams({ _f: () => {} }, (m) => warns.push(String(m))).ok).to.equal(true);
    // stripped BEFORE the function scan — reserved keys never reject
  });

  it("non-object scalars are rejected", () => {
    expect(normalizeParams(7).ok).to.equal(false);
    expect(normalizeParams("x").ok).to.equal(false);
  });
});

describe("runPipeline onion (§6.4)", () => {
  const invokeOf = (rec) => (p) => { rec.push(p); return { done: true }; };

  it("first-registered interceptor is OUTERMOST", () => {
    const order = [];
    const rec = [];
    const out = runPipeline({
      interceptors: [
        (p, next) => { order.push("A"); return next(); },
        (p, next) => { order.push("B"); return next(); },
      ],
      invoke: invokeOf(rec),
      params: { step: 1 },
    });
    expect(out).to.deep.equal({ status: "applied", value: { done: true } });
    expect(order).to.deep.equal(["A", "B"]);
    expect(rec[0]).to.deep.equal({ step: 1 }); // invoke receives snake params
  });

  it("camelCase at every interceptor boundary; snake at invoke", () => {
    const seen = [];
    const rec = [];
    runPipeline({
      interceptors: [
        (p, next) => { seen.push(p); return next({ itemValue: 7 }); },
        (p, next) => { seen.push(p); return next(); },
      ],
      invoke: invokeOf(rec),
      params: { item_value: 1 },
    });
    expect(seen[0]).to.deep.equal({ itemValue: 1 }); // camel inbound
    expect(seen[1]).to.deep.equal({ itemValue: 7 }); // override flows down, camel
    expect(rec[0]).to.deep.equal({ item_value: 7 }); // snake at the Elixir side
  });

  it("veto: not calling next cancels; the stage's return becomes the value", () => {
    let invoked = false;
    const vetoReturn = { no: "go" };
    const out = runPipeline({
      interceptors: [() => vetoReturn, (p, next) => next()],
      invoke: () => { invoked = true; },
      params: {},
    });
    expect(out).to.deep.equal({ status: "vetoed", value: vetoReturn });
    expect(invoked).to.equal(false);
  });

  it("returning a thenable WITHOUT calling next vetoes with the resolved value", async () => {
    const out = runPipeline({
      interceptors: [() => Promise.resolve("veto-async")],
      invoke: () => ({ done: true }),
      params: {},
    });
    expect(out.status ?? (await out).status).to.equal("vetoed");
    const settled = await Promise.resolve(out);
    expect(settled.value).to.equal("veto-async");
  });

  it("throwing BEFORE next stops downstream stages ⇒ error outcome", () => {
    let inner = 0;
    const out = runPipeline({
      interceptors: [
        () => { throw new Error("boom"); },
        (p, next) => { inner += 1; return next(); },
      ],
      invoke: () => ({ done: true }),
      params: {},
    });
    expect(out.status).to.equal("error");
    expect(out.error.message).to.equal("boom");
    expect(out.applied).to.equal(undefined);
    expect(inner).to.equal(0);
  });

  it("throwing AFTER next still marks the ran action applied (§6.4 no rollback)", () => {
    const out = runPipeline({
      interceptors: [(p, next) => { next(); throw new Error("late"); }],
      invoke: () => ({ done: true }),
      params: {},
    });
    expect(out.status).to.equal("error");
    expect(out.applied).to.equal(true);
    expect(out.invokeValue).to.deep.equal({ done: true });
  });

  it("rejected params ⇒ error outcome before any stage runs", () => {
    let touched = 0;
    const out = runPipeline({
      interceptors: [() => { touched += 1; }],
      invoke: () => { touched += 1; },
      params: { fn: () => {} },
    });
    expect(out.status).to.equal("error");
    expect(out.error.message).to.include("data-only");
    expect(touched).to.equal(0);
  });

  it("async chain: awaited stage still applies the action's return", async () => {
    const out = await runPipeline({
      interceptors: [async (p, next) => { await Promise.resolve(); return next(); }],
      invoke: () => ({ done: true }),
      params: {},
    });
    expect(out).to.deep.equal({ status: "applied", value: { done: true } });
  });

  it("stale-drop (U6): async settle after disconnect applies nothing", async () => {
    let connected = true;
    const out = await runPipeline({
      interceptors: [async (p, next) => { await Promise.resolve(); return next(); }],
      invoke: () => ({ done: true }),
      params: {},
      isConnected: () => connected,
    });
    expect(out.status).to.equal("applied");
    connected = false;
    let invoked = false;
    const stale = await runPipeline({
      interceptors: [
        async (p, next) => {
          connected = false; // disconnect happens WHILE the pipeline runs
          return next();
        },
      ],
      invoke: () => { invoked = true; return { done: true }; },
      params: {},
      isConnected: () => connected,
    });
    expect(stale).to.deep.equal({ status: "stale" });
  });

  it("no interceptors ⇒ straight invoke", () => {
    const out = runPipeline({ interceptors: [], invoke: () => 7, params: undefined });
    expect(out).to.deep.equal({ status: "applied", value: 7 });
  });
});
