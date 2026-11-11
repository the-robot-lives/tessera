// Tessera Holo element shell (Tier 2 spike).
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
//   * spike item B element API (no Hologram imports, no
//     globalThis.Hologram access from the extender's side):
//       el.onAction(name, (params, next) => ...)
//       el.dispatchAction(name, params)
//       el.state                      // read-only plain-object snapshot
//       el.setProps({...})            // property/JS API
//       class X extends customElements.get("...") { transformProps(p) {...} }
//         — documented overridable hooks: `transformProps(props)` (last
//         chance to alter props before mount/update) and `onActionError(name, error)`.

import {
  isRuntimeReady,
  mountComponent,
  getDescriptor,
  kebabToSnake,
  camelKeysDeep,
  snakeKeysDeep,
} from "./tessera_holo.mjs";

const RESERVED_ATTRS = new Set(["tsr-props", "module", "class", "id", "style", "slot"]);

const tagModules = new Map();

export class TesseraHoloElement extends HTMLElement {
  static get observedAttributes() {
    return ["tsr-props"];
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

  // spike item B — intercept an action before the Hologram interpreter
  // runs it; `next(params?)` continues (with replacement params), not
  // calling it swallows the action.
  onAction(actionName, hook) {
    if (!this.__mount) return;

    this.__mount.hook(actionName, (params, next) => {
      try {
        return hook(params, next);
      } catch (error) {
        this.onActionError(actionName, error);
        return undefined;
      }
    });
  }

  // spike item B — invoke a component action from host JS
  dispatchAction(actionName, params) {
    if (!this.__mount) return undefined;

    return this.__mount.dispatchAction(actionName, params);
  }

  // spike item B — read-only plain-object state snapshot
  get state() {
    return this.__mount ? this.__mount.stateSnapshot() : null;
  }

  // private methods --------------------------------------------------------

  #mount(moduleName) {
    if (!this.shadowRoot) {
      this.attachShadow({mode: "open"});
    }

    this.__mount = mountComponent(this.shadowRoot, moduleName, this.transformProps(this.#gatherProps()), {
      element: this,
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
    // hook) under a new tag of its own.
    customElements.define(tagName, elementClass);
  }
}
