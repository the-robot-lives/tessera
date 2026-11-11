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

const tagModules = new Map();

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

export function defineElement(tagName, moduleName, elementClass = TesseraHoloElement) {
  const key = tagName.toUpperCase();

  if (tagModules.has(key) && tagModules.get(key) !== moduleName) {
    // Same-tag layering (EXTENSION-CONTRACT v0.1): a derived component may
    // take over the vendor's tag as an EXTENSION, never a substitute — the
    // derived module must keep the vendor behaviour reachable (compile-time
    // layering via the macro-injected base_action/3 dispatcher).
    //
    // The custom element CLASS cannot be redefined once registered (platform
    // spec) — so the tag→module map is repointed instead: elements that
    // CONNECT from now on resolve the derived module. Already-connected
    // instances keep the module they mounted with; layering new behaviour
    // onto those happens through the onAction interceptor chain.
    // eslint-disable-next-line no-console
    console.debug(
      `[tessera-holo] tag <${tagName.toLowerCase()}> layering: ` +
        `${tagModules.get(key)} -> ${moduleName}`,
    );
  }

  tagModules.set(key, moduleName);

  if (!customElements.get(tagName)) {
    // elementClass lets host JS register a SUBCLASS (extension item B:
    // `class X extends customElements.get(tag)` overriding a documented
    // hook) under a new tag of its own. Each tag gets its own anonymous
    // subclass regardless — the registry REJECTS a constructor that was
    // already used for another tag (NotSupportedError).
    const Base = elementClass;
    const TagClass = class extends Base {};

    // §6.1 static surface, read off the component manifest. manifest.actions
    // / manifest.extension_api populate from the compiled spec with brief 3f;
    // until then the documented fallbacks stand (open-surface list [] —
    // dispatch stays name-driven, D2).
    const manifest = getDescriptor(moduleName);

    TagClass.tesseraTag = tagName.toLowerCase();
    TagClass.tesseraContractVersion = 1;
    TagClass.tesseraExtensionApi = (manifest && manifest.extension_api) || "1.0.0";
    TagClass.tesseraActions = Object.freeze([...((manifest && manifest.actions) || [])]);

    customElements.define(tagName, TagClass);
  }
}
