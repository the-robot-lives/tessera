// Tessera Holo element shell (Tier 2).
//
// Standard custom element: one isolated Hologram component instance per
// element, mounted into the element's open shadow root.
//
//   * observed attributes (kebab/snake, cast via the component's compiled
//     prop contract) and the `tsr-props` JSON attribute (camelCase keys,
//     CONTRACT.md §1) both feed props,
//   * mount on connect, teardown on disconnect, re-render on prop change,
//   * component emits (put_action at the synthetic "<cid>$h" bridge) are
//     re-dispatched as composed, bubbling CustomEvents — picked up by the
//     existing `data-tsr-on` bridge on Hologram hosts, plain
//     addEventListener anywhere else,
//   * the element implements the EXTENSION-CONTRACT §6 instance surface,
//     identical to Tier 1 (§9 runtime equivalence):
//       el.state                      // fresh frozen camelCase snapshot +
//                                     // non-enumerable snake aliases (§6.2);
//                                     // frozen {} pre-mount, never null
//       el.onAction(name, interceptor) // element-owned onion chain (first =
//                                     // outermost); returns unsubscribe;
//                                     // survives disconnect/reconnect, works
//                                     // pre-mount (§6.4)
//       el.dispatchAction(name, params) // DispatchResult | Promise<...>
//                                     // (§6.3); either casing; open surface
//       el.setProps({...})            // property/JS API
//       transitions fire `tsr-state-change` on the element after re-render
//       (§6.2 — not bridge traffic); pipeline failures fire
//       `tsr-action-error` (§6.4)
//     class X extends customElements.get("...") { transformProps(p) {...} }
//       — documented overridable hooks: `transformProps(props)` (last
//       chance to alter props before mount/update) and `onActionError(name, error)`.
//     Brief 3c adds the LIFECYCLE projection (client-side only — Hologram
//     init/3 never replays in the browser): `willUpdate(changed)` before the
//     patch, `firstUpdated(changed)` once after the element's first render,
//     `updated(changed)` after every render — `changed` a plain object of
//     OLD values (camelCase props+state); plus the render fences
//     `el.updateComplete` (awaitable) and `el.hasUpdated` (boolean).

import {
  isRuntimeReady,
  mountComponent,
  getDescriptor,
  normalizeActionName,
  kebabToSnake,
  camelKeysDeep,
  snakeKeysDeep,
  EMPTY_SNAPSHOT,
} from "./tessera_holo.mjs";

const RESERVED_ATTRS = new Set(["tsr-props", "module", "class", "id", "style", "slot"]);

// tag (UPPER) -> mount module resolved by the §5.9 chain (see defineElement).
const tagModules = new Map();

// Tags whose element class THIS wrapper already registered with
// customElements. Past this point JS mixins can no longer compose (the
// platform forbids redefining a class); module layers still can — the mount
// module is resolved per-connect from tagModules.
const definedTags = new Set();

// brief 3f — §5.9 takeover registry (Tier-2 mirror of priv/js/src/extend.mjs).
// Lives on globalThis under a Symbol.for key so duplicate bundle copies share
// ONE queue and ONE sequence counter (same trick as the internal-action warn
// set below). Entries are chain coordinates + either a JS mixin
// (extendElement) or a module layer (a repeated defineElement call).
const REGISTRY_KEY = Symbol.for("tessera.holo.extensions");
const EXTEND_WARNED_KEY = Symbol.for("tessera.holo.extend.warned");

function extensionRegistry() {
  let reg = globalThis[REGISTRY_KEY];

  if (!reg || !(reg.extensions instanceof Map)) {
    reg = {extensions: new Map(), extendSeq: 0};
    globalThis[REGISTRY_KEY] = reg;
  }

  return reg;
}

function extendWarnedTags() {
  let set = globalThis[EXTEND_WARNED_KEY];

  if (!(set instanceof Set)) {
    set = new Set();
    globalThis[EXTEND_WARNED_KEY] = set;
  }

  return set;
}

// Registration-order fallback (§6.4 onion rule): first-registered OUTERMOST,
// so a later registration sorts closer to the base on a perfect tie.
function nextExtendSeq(reg) {
  reg.extendSeq = (reg.extendSeq ?? 0) + 1;
  return reg.extendSeq;
}

// §5.9 chain comparator, innermost → outermost. Mirror of
// `Noizu.Tessera.Component.Extension.chain_order/1` (and of the Tier-1
// extend.mjs comparator): dependency depth ASC, priority ASC, module name
// ASC, then first-registered outermost (seq DESC) on a perfect tie.
function compareLayers(a, b) {
  if (a.depth !== b.depth) return a.depth - b.depth;
  if (a.priority !== b.priority) return a.priority - b.priority;
  if (a.module !== b.module) return a.module < b.module ? -1 : 1;
  return b.seq - a.seq;
}

// Queue a MODULE layer: a compiled takeover module whose behaviour lives in
// its own bundle. Module layers carry no JS mixin — they compete (by chain
// coordinates) for which module the composed element MOUNTS: the outermost
// module layer's compiled chain already contains every inner layer (the
// macro-injected base_action/3 dispatcher), so mounting it runs the whole
// chain, markers included.
function queueModuleLayer(tag, moduleName, opts) {
  const reg = extensionRegistry();
  const queue = reg.extensions.get(tag) ?? [];
  const entry = {
    mixin: null,
    depth: Number.isInteger(opts?.depth) ? opts.depth : 0,
    priority: Number.isInteger(opts?.priority) ? opts.priority : 0,
    module: moduleName,
    seq: nextExtendSeq(reg),
  };

  // Duplicate copies of one generated layer re-register the SAME module
  // string — keep the first (extend.mjs dedupe analogue).
  if (queue.some((e) => e.module === moduleName)) return;
  queue.push(entry);
  reg.extensions.set(tag, queue);
}

// Outermost entry WITH a module string — the mount module for the chain.
function outermostModule(entries, fallback) {
  const sorted = entries.slice().sort(compareLayers);

  for (let i = sorted.length - 1; i >= 0; i--) {
    if (typeof sorted[i].module === "string" && sorted[i].module !== "") return sorted[i].module;
  }

  return fallback;
}

// internal: registration warn-once (EXTENSION-CONTRACT §6.4, D2/§10) — the
// SAME global set as the Tier-1 mixin (`Symbol.for`), so both tiers dedupe
// identically per tag+action and the advisory message matches on substring.
const WARNED_INTERNAL_KEY = Symbol.for("tessera.warned-internal");
const warnedInternalActions = (globalThis[WARNED_INTERNAL_KEY] ??= new Set());

export class TesseraHoloElement extends HTMLElement {
  static get observedAttributes() {
    return ["tsr-props"];
  }

  constructor() {
    super();

    // Element-owned action hooks (EXTENSION-CONTRACT §6.4): the registry
    // lives on the ELEMENT, not the mount instance — registrations survive
    // disconnect/reconnect and can be made pre-mount. mountComponent mounts
    // this same Map into its instance, so live mounts see it immediately.
    this.__tesseraHooks = new Map();

    // brief 3c: element-lifetime render latch (lit-parity §2.1 rows #10/#18).
    // Set by the shim after the element's FIRST committed render — survives
    // disconnect/reconnect so firstUpdated fires exactly once per element
    // lifetime (Lit parity) and hasUpdated keeps its value across remounts.
    this.__tesseraEverRendered = false;

    // brief 3e: form association (lit-parity §2.10 rows #144-#149;
    // EXTENSION-CONTRACT §6.7). `static formAssociated` is decided at
    // customElements.define by defineElement — from the compiled manifest
    // (manifest.formAssociated === true, which brief 3f will drive from the
    // spec's form_associated; today a fixture opts in via
    // __tsr_form_associated__/0) or from the base class's own static (the
    // documented subclass seam). attachInternals() THROWS NotSupportedError
    // on a non-form-associated element, so it is gated on new.target — the
    // actually-constructed class, statics and all — and a non-declared
    // element NEVER gets internals attached (§6.7 MUST NOT).
    this.__tesseraInternals = new.target.formAssociated === true ? this.attachInternals() : null;
  }

  // Documented overridable hook: alter props before every mount/update.
  transformProps(props) {
    return props;
  }

  // Documented overridable hook: observe action errors (default: log).
  onActionError(name, error) {
    // eslint-disable-next-line no-console
    console.error(`[tessera-holo] action '${name}' failed`, error);
  }

  // --- brief 3c: lifecycle projection hooks (lit-parity §2.1 rows #7/#10/
  // #11/#34). The shim calls these from renderInstance — Hologram's JS.call
  // in init/3 is a SERVER-side pass-through and never replays client-side,
  // so the lifecycle lives entirely client-side in the shim's render loop,
  // NOT in Elixir init. `changed` is a PLAIN object of OLD values (camelCase
  // props+state keys, STATE wins on collision) — never a live Map; the FIRST
  // render's willUpdate sees props only (the state struct is registered by
  // renderDom itself — honest runtime limitation, documented row #7). Hook
  // errors are caught+warned and never abort the shared render loop (Tier-2
  // divergence from Lit, which propagates). SHOULD call super.
  willUpdate(_changed) {} // eslint-disable-line no-unused-vars

  firstUpdated(_changed) {} // eslint-disable-line no-unused-vars

  updated(_changed) {} // eslint-disable-line no-unused-vars

  // Awaitable render fence (lit-parity §2.1 rows #12/#220; the getter
  // override is also the subclass seam that replaces Lit's protected
  // getUpdateComplete — row #13). Resolves when the render cycle observed
  // at access time commits: reentrant access (inside a hook / during a
  // render) queues behind that render; access at idle resolves on the next
  // microtask — Tier-2 commits render SYNCHRONOUSLY inside dispatchAction/
  // setProps, so the DOM is already current by then. For an async-stage
  // dispatch, await the dispatchAction Promise FIRST. Pre-mount: resolves
  // immediately — there is nothing to fence.
  get updateComplete() {
    return this.__mount ? this.__mount.updateComplete() : Promise.resolve();
  }

  // True after the element's first committed render (lit-parity row #18).
  // Element-persistent: stays true across disconnect/reconnect.
  get hasUpdated() {
    return this.__tesseraEverRendered === true;
  }

  // --- brief 3e: form participation surface (EXTENSION-CONTRACT §6.7;
  // lit-parity §2.10 rows #144-#149) ------------------------------------------
  // ElementInternals for a DECLARED form-associated tag (#145) — the handle
  // authors push values through setFormValue (#147) and validation states
  // through setValidity (#146). `null` for every non-declared element: the
  // internals is NEVER attached otherwise (§6.7 MUST NOT), and reading it
  // never throws — authors branch on `el.internals !== null`.
  get internals() {
    return this.__tesseraInternals;
  }

  // Form lifecycle seams (#148/#149). The browser invokes these ONLY on a
  // form-associated custom element, so defining them is harmless on a
  // declared-false tag. The defaults are NO-OPS: the wrapper never guesses a
  // reset/-disable policy — a fixture or host subclass overrides them (and
  // SHOULD call super). Wiring a reset to an action, or a value to
  // setFormValue, is the author's contract (see the holo_kit FormProbe
  // fixture + the glue recording subclass for the documented pattern).
  formResetCallback() {}

  // eslint-disable-next-line no-unused-vars
  formDisabledCallback(_disabled) {}

  connectedCallback() {
    if (this.__mount) return;

    const moduleName = this.getAttribute("module") || tagModules.get(this.tagName.toUpperCase());

    if (!moduleName) {
      // eslint-disable-next-line no-console
      console.error(`[tessera-holo] no component module registered for <${this.tagName.toLowerCase()}>`);
      return;
    }

    this.__moduleName = moduleName;
    this.__actionErrorHook = null;

    if (!isRuntimeReady()) {
      // Defensive: script order normally guarantees the runtime first.
      const retry = (attempts) => {
        if (this.__mount || !this.isConnected) return;

        if (isRuntimeReady()) {
          this.#mount(moduleName);
        } else if (attempts < 100) {
          setTimeout(() => retry(attempts + 1), 50);
        } else {
          // eslint-disable-next-line no-console
          console.error("[tessera-holo] runtime never initialized");
        }
      };

      retry(0);
      return;
    }

    this.#mount(moduleName);
  }

  disconnectedCallback() {
    if (!this.__mount) return;

    this.__mount.destroy();
    this.__mount = null;
    // __tesseraHooks deliberately SURVIVES — interceptor registrations are
    // per-element and outlive connections (§6.4).
  }

  attributeChangedCallback(name, oldValue, newValue) {
    if (name !== "tsr-props" || oldValue === newValue) return;
    if (!this.__mount) return;

    // full re-derive: tsr-props may change any prop
    this.__mount.setProps(this.transformProps(this.#gatherProps()));
  }

  // property/JS API — set/merge props programmatically (React hosts)
  setProps(props) {
    if (!this.__mount) return;

    this.__mount.setProps(this.transformProps({...this.#gatherProps(), ...snakeKeysDeep(props)}));
  }

  // EXTENSION-CONTRACT §6.4 — intercept an action before the Hologram
  // interpreter runs it. Name accepted in snake/camel/kebab case; storage is
  // element-owned, so registration works pre-mount and across
  // disconnect/reconnect. Onion order: FIRST-registered OUTERMOST (D3).
  // Returns the unsubscribe function. `next(params?)` continues (with
  // replacement params in either casing); not calling it VETOES the action —
  // no downstream stage runs, no state change, no events (§6.4). A stage
  // that throws surfaces to the pipeline (tsr-action-error +
  // {ok:false, reason:"error"}) after onActionError observes it.
  onAction(actionName, hook) {
    const key = normalizeActionName(actionName);

    // `internal: true` is ADVISORY, never access control (D2/§10): the
    // action stays open (dispatch + interception work); registering against
    // one fires a dev-mode warn ONCE per tag+action (§6.4, X-07 pins the
    // count). The manifest list arrives via the component_manifest's
    // `internalActions` key — absent ⇒ no warn (Tier-1 parity).
    const moduleName =
      this.__moduleName || this.getAttribute("module") || tagModules.get(this.tagName.toUpperCase());
    const manifest = moduleName ? getDescriptor(moduleName) : null;
    const internalSet = new Set(
      (Array.isArray(manifest?.internalActions) ? manifest.internalActions : [])
        .filter((n) => typeof n === "string"),
    );

    if (internalSet.has(key)) {
      const tag = this.tagName.toLowerCase();
      const dedupe = `${tag}:${key}`;

      if (!warnedInternalActions.has(dedupe)) {
        warnedInternalActions.add(dedupe);
        // eslint-disable-next-line no-console
        console.warn(
          `[tessera-holo] <${tag}> interceptor registered against internal action "${key}" — ` +
            "the internal: annotation is advisory (EXTENSION-CONTRACT.md §6.4); the interception works",
        );
      }
    }

    const chain = this.__tesseraHooks.get(key) || [];

    const wrapped = (params, next) => {
      try {
        return hook(params, next);
      } catch (error) {
        this.onActionError(actionName, error);
        throw error;
      }
    };

    chain.push(wrapped);
    this.__tesseraHooks.set(key, chain);

    return () => {
      const current = this.__tesseraHooks.get(key) || [];
      const at = current.indexOf(wrapped);

      if (at >= 0) current.splice(at, 1);
    };
  }

  // EXTENSION-CONTRACT §6.3 — invoke a component action from host JS.
  // Returns DispatchResult (or Promise<DispatchResult> when a stage is
  // async): {ok:true, value: post-transition snapshot} on commit;
  // {ok:false, reason:"unknown-action"} on unknown names (warn, nothing
  // emitted); {ok:false, reason:"vetoed"} on stage cancellation or a stale
  // post-disconnect resolution (U6); {ok:false, reason:"error"} on stage /
  // action errors (plus tsr-action-error).
  dispatchAction(actionName, params) {
    if (!this.__mount) {
      // eslint-disable-next-line no-console
      console.warn(
        `[tessera-holo] dispatchAction('${actionName}') before mount — no component instance`,
      );

      return {ok: false, reason: "error"};
    }

    return this.__mount.dispatchAction(actionName, params);
  }

  // EXTENSION-CONTRACT §6.2 — fresh frozen snapshot per access: canonical
  // camelCase keys + NON-ENUMERABLE snake_case aliases; top-level frozen
  // only (nested values shared, treat as read-only). Pre-mount /
  // post-destroy: the frozen EMPTY snapshot — never null.
  get state() {
    return this.__mount ? this.__mount.stateSnapshot() || EMPTY_SNAPSHOT : EMPTY_SNAPSHOT;
  }

  // private methods --------------------------------------------------------

  #mount(moduleName) {
    if (!this.shadowRoot) {
      this.attachShadow({mode: "open"});
    }

    this.__mount = mountComponent(this.shadowRoot, moduleName, this.transformProps(this.#gatherProps()), {
      element: this,
      hooks: this.__tesseraHooks,
    });
  }

  #gatherProps() {
    const manifest = getDescriptor(this.__moduleName) || {props: []};
    const propsBySnake = new Map(manifest.props.map((p) => [p.name, p]));

    const props = {};

    // 1. attributes (kebab -> snake prop name), cast via the contract
    for (const attr of this.attributes) {
      const name = attr.name.toLowerCase();

      if (RESERVED_ATTRS.has(name)) continue;
      if (name.startsWith("data-") || name.startsWith("aria-")) continue;

      const propName = kebabToSnake(name);
      const propDef = propsBySnake.get(propName);

      if (!propDef) continue; // unknown attr — not a contract prop

      props[propName] = castAttr(attr.value, propDef.type);
    }

    // 2. tsr-props JSON (camelCase keys -> snake), overrides attributes
    const tsrProps = this.getAttribute("tsr-props");

    if (tsrProps) {
      let parsed;

      try {
        parsed = JSON.parse(tsrProps);
      } catch (error) {
        // eslint-disable-next-line no-console
        console.error("[tessera-holo] invalid tsr-props JSON", error);
        parsed = null;
      }

      if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
        Object.assign(props, snakeKeysDeep(camelKeysDeep(parsed)));
      }
    }

    return props;
  }
}

function castAttr(value, type) {
  switch (type) {
    case "integer":
      return parseInt(value, 10);
    case "float":
      return parseFloat(value);
    case "boolean":
      return value !== "false" && value !== "";
    case "atom":
      return value;
    default:
      return value;
  }
}

// brief 3f — §5.9 takeover registry, JS-mixin lane (Tier-2 mirror of the
// Tier-1 extendElement). Queues `(Base) => class extends Base {…}` beside
// defineElement; the queue composes into the SINGLE class defineElement
// registers at the tag's FIRST definition — duplicate bundle copies never
// double-wrap (module-string dedupe; hand-written mixins without a module
// string never dedupe). Ordering is the §5.9 chain via compareLayers.
//
// Registering for an ALREADY-DEFINED tag cannot layer onto the class
// anymore: warn-once, return false, and point at the sanctioned post-define
// paths — onAction interceptors (§6.4). Module layers (compiled takeover
// bundles) keep layering past define via repeated defineElement calls —
// the mount module is resolved per-connect, not per-class.
//
// @param {string} tag
// @param {(base: CustomElementConstructor) => CustomElementConstructor} mixin
// @param {{depth?: number, priority?: number, module?: string}} [opts]
//   §5.9 chain coordinates: `depth` = layers above the vendor base,
//   `priority` = the `use …, priority: n` option, `module` = declaring
//   module string (also the duplicate-copy dedupe key).
// @returns {boolean} true when queued (or deduped); false post-define.
export function extendElement(tag, mixin, opts = {}) {
  if (typeof mixin !== "function") {
    throw new TypeError(`[tessera-holo] extendElement("${tag}") requires a mixin function (Base) => class`);
  }

  const key = tag.toUpperCase();

  if (customElements.get(tag) || definedTags.has(key)) {
    const warned = extendWarnedTags();

    if (!warned.has(tag)) {
      warned.add(tag);
      // eslint-disable-next-line no-console
      console.warn(
        `[tessera-holo] <${tag}> is already defined; extendElement cannot layer onto an existing class — ` +
          "use onAction for pipeline wrapping (§6.4), or a compiled takeover module via defineElement (§5.9).",
      );
    }

    return false;
  }

  const reg = extensionRegistry();
  const queue = reg.extensions.get(key) ?? [];
  const module = typeof opts.module === "string" ? opts.module : "";

  if (module !== "" && queue.some((entry) => entry.module === module)) return true;

  queue.push({
    mixin,
    depth: Number.isInteger(opts.depth) ? opts.depth : 0,
    priority: Number.isInteger(opts.priority) ? opts.priority : 0,
    module,
    seq: nextExtendSeq(reg),
  });
  reg.extensions.set(key, queue);

  return true;
}

export function defineElement(tagName, moduleName, elementClass = TesseraHoloElement, opts = {}) {
  const key = tagName.toUpperCase();
  const reg = extensionRegistry();

  if (!definedTags.has(key) && !customElements.get(tagName)) {
    // FIRST definition (EXTENSION-CONTRACT §5.9): this call's module joins
    // the chain as the vendor base (depth 0 unless the caller passes
    // coordinates — import order must not decide the chain), then the whole
    // queue composes: JS mixins reduce-wrap the element class (outermost
    // mixin applied last), and the OUTERMOST module layer names the module
    // the composed class mounts — its compiled base_action/3 chain already
    // contains every inner layer.
    queueModuleLayer(key, moduleName, opts);

    const entries = reg.extensions.get(key) ?? [];
    const sorted = entries.slice().sort(compareLayers);
    const mountModule = outermostModule(entries, moduleName);

    const composed = sorted.reduce((Base, entry) => (entry.mixin ? entry.mixin(Base) : Base), elementClass);

    // elementClass lets host JS register a SUBCLASS (extension item B:
    // `class X extends customElements.get(tag)` overriding a documented
    // hook) under a new tag of its own. Each tag gets its own anonymous
    // subclass regardless — the registry REJECTS a constructor that was
    // already used for another tag (NotSupportedError).
    const TagClass = class extends composed {};

    // §6.1 static surface, read off the component manifest (the composed
    // class's own statics — a JS mixin seam — also count, additive only).
    const manifest = getDescriptor(mountModule);

    // brief 3e (§6.7, #144): formAssociated is decided HERE, before define —
    // it is read by customElements.define off the constructor, and the
    // constructor's gated attachInternals reads it off new.target per
    // instance. Sources, all additive: the compiled manifest of the mount
    // module (standalone.ex emits it spec-first — `__tessera_spec__().
    // form_associated` — with the brief 3e fixture hook as fallback), the
    // host-provided element class's `static formAssociated = true`
    // (subclass seam), or a JS mixin's static. NEVER unsettable once a base
    // has it — inherited surface cannot be narrowed (§5.9 final rule).
    if ((manifest && manifest.formAssociated) === true || composed.formAssociated === true) {
      TagClass.formAssociated = true;
    }

    TagClass.tesseraTag = tagName.toLowerCase();
    TagClass.tesseraContractVersion = 1;
    TagClass.tesseraExtensionApi = (manifest && manifest.extension_api) || "1.0.0";
    TagClass.tesseraActions = Object.freeze([...((manifest && manifest.actions) || [])]);

    tagModules.set(key, mountModule);
    definedTags.add(key);

    customElements.define(tagName, TagClass);

    // consume the queue — past-define registrations cannot compose (see
    // extendElement) and stale entries must not re-wrap a later caller.
    reg.extensions.delete(key);
  } else {
    // ALREADY-DEFINED tag: compiled takeover layers still compose — the
    // class is fixed, but the MOUNT MODULE is resolved per-connect from
    // tagModules, so re-pointing it to the chain-outermost module layers
    // new behaviour onto every element that connects from now on
    // (already-connected instances keep the module they mounted with; live
    // layering onto those happens through the onAction interceptor chain).
    queueModuleLayer(key, moduleName, opts);

    const entries = reg.extensions.get(key) ?? [];
    const mountModule = outermostModule(entries, tagModules.get(key));

    if (mountModule !== tagModules.get(key)) {
      // eslint-disable-next-line no-console
      console.debug(
        `[tessera-holo] tag <${tagName.toLowerCase()}> chain layering: ` +
          `${tagModules.get(key)} -> ${mountModule}`,
      );

      tagModules.set(key, mountModule);
    }
  }
}
