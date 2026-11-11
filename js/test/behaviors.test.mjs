import { expect } from "@open-wc/testing";
import { TesseraElement } from "../../priv/js/src/element.mjs";
import { defineOnce } from "../../priv/js/src/define.mjs";
import { behaviors, behaviorsAdd, behaviorsRemove, behaviorsFor, checkApiPin } from "../../priv/js/src/behaviors.mjs";
import { PLAIN_TAG, plainContract, captureWarns } from "./helpers.mjs";

// FAST group (§6.5 + §8.4, brief 2f): the behaviors registry contract —
// unsubscribe return, pin semantics at connect (skip-on-major U3/Q1,
// minor-warn-only), warn-once per tag+extender, remove/unsubscribe
// equivalence — plus the §6.7 form-participation gate on the mixin
// (internals attach ONLY for classes that declare `static formAssociated`).

describe("behaviors registry (§6.5)", () => {
  // element.test.mjs registers PLAIN_TAG in ITS own before() — this file
  // needs its own registration to upgrade elements (custom elements only
  // upgrade when a definition exists in this document).
  before(() => {
    class PlainEl extends TesseraElement(HTMLElement, plainContract) {}
    defineOnce(PLAIN_TAG, PlainEl);
  });

  afterEach(() => {
    for (const fn of behaviorsFor(PLAIN_TAG)) behaviorsRemove(PLAIN_TAG, fn);
  });

  function make() {
    const el = document.createElement(PLAIN_TAG);
    document.body.appendChild(el);
    return el;
  }

  it("add returns an unsubscribe function; calling it deregisters", () => {
    const fn = () => {};
    const unsub = behaviors.add(PLAIN_TAG, fn);
    expect(unsub).to.be.a("function");
    expect(behaviorsFor(PLAIN_TAG)).to.include(fn);
    unsub();
    expect(behaviorsFor(PLAIN_TAG)).to.not.include(fn);
    // Idempotent: a second call is a no-op, not a throw.
    expect(() => unsub()).to.not.throw();
  });

  it("re-adding the same fn keeps Set semantics and refreshes its pin", () => {
    let runs = 0;
    const fn = () => {
      runs += 1;
    };
    const unsub1 = behaviors.add(PLAIN_TAG, fn, {api: "^0.9.0"});
    // Same fn re-registered: Set dedupe keeps one entry; the pin REFRESHES.
    const unsub2 = behaviors.add(PLAIN_TAG, fn, {api: "^1.0.0"});
    expect(behaviorsFor(PLAIN_TAG).filter((f) => f === fn)).to.have.lengthOf(1);
    const el = make();
    expect(runs).to.equal(1, "duplicate registration runs once per connect");
    unsub1();
    unsub2();
    el.remove();
  });

  it("unsubscribe is equivalent to behaviors.remove", () => {
    const a = () => {};
    const b = () => {};
    const unsubA = behaviors.add(PLAIN_TAG, a);
    behaviors.add(PLAIN_TAG, b);
    unsubA();
    behaviorsRemove(PLAIN_TAG, b);
    expect(behaviorsFor(PLAIN_TAG)).to.deep.equal([]);
  });

  it("an api pin is checked at CONNECT, not at registration", () => {
    // The tag has a live runtime already, but registration must not gate on
    // it — the pin decision happens per connect (§8.4), so a behavior pinned
    // before its element ever loads still registers cleanly.
    let runs = 0;
    const fn = () => {
      runs += 1;
    };
    expect(() => behaviors.add(PLAIN_TAG, fn, { api: "^9.0.0" })).to.not.throw();
    expect(behaviorsFor(PLAIN_TAG)).to.include(fn);
    expect(runs).to.equal(0, "registration alone never invokes the fn");
  });

  describe("api pin at connect (§8.4, U3/Q1 skip-on-major)", () => {
    const PIN_TAG = "tsr-behavior-pin";
    const pinContract = { ...plainContract, tag: PIN_TAG };

    before(() => {
      class PinEl extends TesseraElement(HTMLElement, pinContract, { extensionApi: "1.4.2" }) {}
      defineOnce(PIN_TAG, PinEl);
    });

    function makePinned() {
      const el = document.createElement(PIN_TAG);
      document.body.appendChild(el);
      return el;
    }

    function pinnedBehavior(tag, api, effect) {
      const fn = effect;
      behaviorsAdd(tag, fn, api === null ? {} : { api });
      return fn;
    }

    it("major mismatch ⇒ warn + SKIP the behavior (element never breaks)", () => {
      let runs = 0;
      const fn = pinnedBehavior(PIN_TAG, "^2.0.0", () => {
        runs += 1;
      });
      let el;
      const warns = captureWarns(() => {
        el = makePinned();
      });
      expect(runs).to.equal(0, "major mismatch skips the behavior (U3)");
      expect(el.isConnected).to.equal(true);
      expect(warns.some((w) => w.includes("SKIPPED") && w.includes("^2.0.0") && w.includes("1.4.2"))).to.equal(true);
      el.remove();
      behaviorsRemove(PIN_TAG, fn);
    });

    it("minor mismatch ⇒ warn only; the behavior still runs", () => {
      let runs = 0;
      const fn = pinnedBehavior(PIN_TAG, "^1.9.0", () => {
        runs += 1;
      });
      let el;
      const warns = captureWarns(() => {
        el = makePinned();
      });
      expect(runs).to.equal(1, "minor mismatch is advisory");
      expect(warns.some((w) => w.includes("minor") && w.includes("^1.9.0"))).to.equal(true);
      el.remove();
      behaviorsRemove(PIN_TAG, fn);
    });

    it("satisfied range ⇒ runs, no pin warning", () => {
      let runs = 0;
      const fn = pinnedBehavior(PIN_TAG, "^1.0.0", () => {
        runs += 1;
      });
      const el = makePinned();
      expect(runs).to.equal(1);
      el.remove();
      behaviorsRemove(PIN_TAG, fn);
    });

    it("warns ONCE per tag+extender across reconnects", () => {
      let runs = 0;
      const fn = pinnedBehavior(PIN_TAG, "^2.0.0", () => {
        runs += 1;
      });
      // First connect — the SKIP warn fires here (major mismatch never runs).
      const first = captureWarns(() => makePinned());
      expect(runs).to.equal(0);
      expect(first.filter((w) => w.includes("SKIPPED"))).to.have.lengthOf(1);
      // Reconnects never re-warn (warn-once per tag+extender) and never run.
      const el = document.querySelector(PIN_TAG);
      const again = captureWarns(() => {
        el.remove();
        document.body.appendChild(el);
        el.remove();
        document.body.appendChild(el);
      });
      expect(runs).to.equal(0, "major mismatch stays skipped on every connect");
      expect(again.filter((w) => w.includes("SKIPPED"))).to.have.lengthOf(0, "warn-once per tag+extender");
      el.remove();
      behaviorsRemove(PIN_TAG, fn);
    });

    it("unparsable range ⇒ warns, gates nothing", () => {
      let runs = 0;
      const fn = pinnedBehavior(PIN_TAG, "not-a-range", () => {
        runs += 1;
      });
      let el;
      const warns = captureWarns(() => {
        el = makePinned();
      });
      expect(runs).to.equal(1, "a broken pin must not silently disable an extender");
      expect(warns.some((w) => w.includes("not-a-range") && w.includes("not parse"))).to.equal(true);
      el.remove();
      behaviorsRemove(PIN_TAG, fn);
    });
  });

  it("checkApiPin: floor + major gate, ^/~/>=/exact all parse", () => {
    expect(checkApiPin("^1.0.0", "1.4.2")).to.equal("ok");
    expect(checkApiPin("~1.2", "1.2.0")).to.equal("ok");
    expect(checkApiPin(">=1", "1.0.0")).to.equal("ok");
    expect(checkApiPin("1.4", "1.4.2")).to.equal("ok");
    expect(checkApiPin("^2.0.0", "1.4.2")).to.equal("major");
    expect(checkApiPin("1", "2.0.0")).to.equal("major");
    expect(checkApiPin("^1.9.0", "1.4.2")).to.equal("minor");
    expect(checkApiPin("1.5", "1.4.2")).to.equal("minor");
    expect(checkApiPin("garbage", "1.0.0")).to.equal("invalid");
    expect(checkApiPin("^1.0.0", undefined)).to.equal("invalid");
  });
});

// §6.7 form participation (brief 2f): the mixin attaches ElementInternals
// ONLY when the class declares `static formAssociated = true` — never for an
// undeclared element (the FM-01 negative, pinned at the core level here and
// end-to-end on the compiled fixture in the FM conformance family).
describe("form participation gate (§6.7)", () => {
  const FORM_TAG = "tsr-behavior-form";
  const formContract = { ...plainContract, tag: FORM_TAG };

  before(() => {
    class Undeclared extends TesseraElement(HTMLElement, formContract) {}
    class Declared extends TesseraElement(HTMLElement, formContract) {
      static formAssociated = true;
    }
    defineOnce(FORM_TAG, Undeclared);
    defineOnce(`${FORM_TAG}-declared`, Declared);
  });

  it("declared ⇒ internals attach and expose setFormValue/setValidity", () => {
    const el = document.createElement(`${FORM_TAG}-declared`);
    document.body.appendChild(el);
    expect(el.constructor.formAssociated).to.equal(true);
    expect(el.internals).to.not.equal(null);
    expect(typeof el.internals.setFormValue).to.equal("function");
    expect(typeof el.internals.setValidity).to.equal("function");
    el.remove();
  });

  it("undeclared ⇒ internals NEVER attach (reads null, not throws)", () => {
    const el = document.createElement(FORM_TAG);
    document.body.appendChild(el);
    expect(el.internals).to.equal(null);
    el.remove();
  });

  it("formResetCallback / formDisabledCallback are overridable no-op seams", () => {
    const signals = [];
    const el = document.createElement(`${FORM_TAG}-declared`);
    el.formResetCallback = () => signals.push("reset");
    el.formDisabledCallback = (disabled) => signals.push(disabled ? "disabled" : "enabled");
    document.body.appendChild(el);
    el.formResetCallback();
    el.formDisabledCallback(true);
    expect(signals).to.deep.equal(["reset", "disabled"]);
    el.remove();
  });
});
