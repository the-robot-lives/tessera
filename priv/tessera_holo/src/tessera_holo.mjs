// Tessera Hologram runtime shim (Tier 2 spike).
//
// One instance of this module is bundled into `tessera-runtime` together
// with the Hologram client runtime (imported from the hologram package's
// own .mjs sources — no fork). The shim:
//
//   1. receives the runtime modules via initRuntime() (called by the
//      generated runtime entry),
//   2. replicates the one piece of `Hologram.run()` a component host needs
//      (`#defineManuallyPortedFunctions`, extracted verbatim upstream),
//      WITHOUT run()'s page machinery (window listeners, history, SSE,
//      Client.connect, #mountPage),
//   3. patches the shim's OWN copy only:
//        - Hologram.executeAction  -> intercepts emit targets ("<cid>$h")
//                                     and per-instance onAction hooks
//        - Hologram.render         -> instance-scoped render loop patching
//                                     each element's shadow-root host div
//        - Client.sendCommand      -> BusClient seam
//      the host page's globalThis.Hologram object (if any) is never
//      written by the shim, and the profiling flag is saved/restored
//      around delegated calls.
//
// Coexistence notes (see docs/notes/spike-hologram-runtime-element.md):
// compiled function defs register on SHARED globalThis module proxies
// (`Elixir_*` / `Erlang_*`). Same hologram version => identical
// registration, overwrite is harmless. Version mismatch => last writer
// wins — the manifest records the compiled hologram version for a
// handshake check.

import {init as snabbdomInit, h} from "snabbdom";
// snabbdom 3.6.4 publishes everything under build/ (no "exports" map), so
// the modules resolve via their full subpath:
import {attributesModule} from "snabbdom/build/modules/attributes.js";
import {eventListenersModule} from "snabbdom/build/modules/eventlisteners.js";import {toVNode} from "snabbdom";

import {takeQueuedComponents} from "./register.mjs";

const HOST_SUFFIX = "$h";

// Hologram 0.10.1 boxed bitstrings carry `.text` (+ bytes/hex), NOT `.value`
// — reading `.value` on one yields undefined. Always go through Bitstring.
function bitstringText(value) {
  return RT.deps.Bitstring.toText(value);
}

let RT = null;
let bus = null;
let cidCounter = 0;

// cid -> instance
const instances = new Map();
// module name -> manifest (prop contract for attribute casting)
const descriptors = new Map();

// ---------------------------------------------------------------------------
// init
// ---------------------------------------------------------------------------

export function initRuntime(runtime) {
  if (RT) return;

  RT = runtime;

  // The stock runtime reads globalThis.Hologram.isProfilingEnabled around
  // every delegated call (interpreter.mjs) and toggles it in executeAction —
  // on non-Hologram hosts that object does not exist, so provide a minimal
  // stub. On a Hologram host the HOST's object is already there and wins.
  globalThis.Hologram ??= {isProfilingEnabled: false};

  RT.defineManuallyPortedFunctions();

  patchExecuteAction();
  patchRender();
  patchSendCommand();

  globalThis.__TesseraHoloApply__ = applyQueuedComponents;
  applyQueuedComponents();
}

export function isRuntimeReady() {
  return RT !== null;
}

export function getDescriptor(moduleName) {
  // Component bundles register descriptors under the full alias
  // ("Elixir.…") but hosts may pass the bare module name — accept both.
  const prefixed = moduleName.startsWith("Elixir.") ? moduleName : "Elixir." + moduleName;

  return descriptors.get(prefixed) || descriptors.get(moduleName) || null;
}

function applyQueuedComponents() {
  if (!RT) return;

  for (const {moduleName, defs, manifest} of takeQueuedComponents()) {
    defs(RT.deps);
    descriptors.set(moduleName, manifest);
  }
}

// ---------------------------------------------------------------------------
// runtime patches (own copy only)
// ---------------------------------------------------------------------------

function patchExecuteAction() {
  const original = RT.Hologram.executeAction;

  RT.Hologram.executeAction = function (action) {
    const Maps = globalThis.Erlang_Maps;
    const T = RT.Type;

    const target = Maps["get/2"](T.atom("target"), action);

    // 1. emit bridge: actions targeted at the synthetic host cid
    if (!T.isNil(target) && T.isBitstring(target) && bitstringText(target).endsWith(HOST_SUFFIX)) {
      return emitDomEvent(bitstringText(target), action);
    }

    // 2. per-instance onAction hooks (spike item B). Action names are
    //    accepted in snake/camel/kebab case (EXTENSION-CONTRACT v0.1); all
    //    actions are open — no allowlist. Multiple hooks on the same action
    //    compose in registration order (middleware chain); skipping next()
    //    swallows the action.
    if (!T.isNil(target) && T.isBitstring(target) && instances.has(bitstringText(target))) {
      const instance = instances.get(bitstringText(target));
      const name = Maps["get/2"](T.atom("name"), action).value;
      const chain = instance.hooks.get(normalizeActionName(name));

      if (chain && chain.length > 0) {
        const params = toJs(Maps["get/2"](T.atom("params"), action));

        const runFrom = (index, currentParams) => {
          if (index >= chain.length) {
            const rebuilt = T.actionStruct({
              name: T.atom(name),
              params: RT.JsInterop.boxActionParam(snakeKeysDeep(currentParams)),
              target: target,
              delay: Maps["get/3"](T.atom("delay"), action, T.integer(0)),
            });

            return runOriginal(original, rebuilt);
          }

          const next = (replacement) =>
            runFrom(index + 1, replacement === undefined ? currentParams : replacement);

          return chain[index](currentParams, next);
        };

        return runFrom(0, params);
      }
    }

    return runOriginal(original, action);
  };
}

function runOriginal(original, action) {
  // executeAction toggles globalThis.Hologram.isProfilingEnabled — on a
  // Hologram host that is the HOST's flag. Save/restore around the call.
  const hostGlobal = globalThis.Hologram;
  const hadFlag = hostGlobal && "isProfilingEnabled" in hostGlobal;
  const prev = hadFlag ? hostGlobal.isProfilingEnabled : undefined;

  try {
    return original(action);
  } finally {
    if (hadFlag) hostGlobal.isProfilingEnabled = prev;
  }
}

function patchRender() {
  RT.Hologram.render = function () {
    for (const instance of instances.values()) {
      renderInstance(instance);
    }
  };
}

function patchSendCommand() {
  const original = RT.Client.sendCommand;

  RT.Client.sendCommand = function (command) {
    if (typeof bus === "function") {
      return bus(command, commandContext(command));
    }

    // eslint-disable-next-line no-console
    console.warn(
      "[tessera-holo] put_command reached with no bus configured — dropping command",
    );

    return Promise.resolve({ok: false, reason: "no-transport"});
  };

  RT.Client.__tesseraOriginalSendCommand = original;
}

function commandContext(command) {
  const T = RT.Type;
  const target = globalThis.Erlang_Maps["get/2"](T.atom("target"), command);
  const cid =
    !T.isNil(target) && (T.isBitstring(target) ? bitstringText(target) : target.value) || null;

  return {instance: instances.get(cid) || null, element: instances.get(cid)?.element || null};
}

// ---------------------------------------------------------------------------
// emit bridge
// ---------------------------------------------------------------------------

function emitDomEvent(targetValue, action) {
  const Maps = globalThis.Erlang_Maps;
  const T = RT.Type;

  const cid = targetValue.slice(0, -HOST_SUFFIX.length);
  const instance = instances.get(cid);

  const name = Maps["get/2"](T.atom("name"), action).value;
  const params = Maps["get/2"](T.atom("params"), action);

  const eventType = snakeToKebab(name);
  const detail = toJs(params);

  const source = instance?.element || instance?.hostDiv;

  if (!source) {
    // eslint-disable-next-line no-console
    console.warn(`[tessera-holo] emit for unknown instance ${cid} dropped`);
    return;
  }

  source.dispatchEvent(new CustomEvent(eventType, {bubbles: true, composed: true, detail}));
}

// ---------------------------------------------------------------------------
// mounting
// ---------------------------------------------------------------------------

export function mountComponent(shadowRoot, moduleName, props = {}, options = {}) {
  if (!RT) {
    throw new Error(
      "[tessera-holo] runtime not initialized — load tessera-runtime before mounting",
    );
  }

  const cid = "tssr_" + String(++cidCounter);

  const hostDiv = document.createElement("div");
  hostDiv.setAttribute("data-tessera-holo-host", "");
  shadowRoot.appendChild(hostDiv);

  const instance = {
    cid,
    moduleName,
    props: {...props},
    shadowRoot,
    hostDiv,
    element: options.element || null,
    patch: null,
    vnode: null,
    hooks: new Map(),
  };

  instances.set(cid, instance);
  renderInstance(instance);

  return {
    cid,
    hostDiv,
    get element() {
      return instance.element;
    },
    hook(actionName, hookFn) {
      // Name normalized (snake/camel/kebab all accepted); hooks compose in
      // registration order. Returns an unsubscribe function.
      const key = normalizeActionName(actionName);
      const chain = instance.hooks.get(key) || [];

      chain.push(hookFn);
      instance.hooks.set(key, chain);

      return () => {
        const current = instance.hooks.get(key) || [];
        const at = current.indexOf(hookFn);

        if (at >= 0) current.splice(at, 1);
      };
    },
    update(nextProps) {
      instance.props = {...instance.props, ...nextProps};
      renderInstance(instance);
    },
    setProps(nextProps) {
      instance.props = {...nextProps};
      renderInstance(instance);
    },
    dispatchAction(actionName, params) {
      return dispatchComponentAction(instance, actionName, params);
    },
    stateSnapshot() {
      return stateSnapshot(instance);
    },
    destroy() {
      destroyInstance(instance);
    },
  };
}

export function setBus(fn) {
  bus = typeof fn === "function" ? fn : null;
}

function renderInstance(instance) {
  const T = RT.Type;
  const I = RT.Interpreter;
  const R = RT.Renderer;

  const moduleAlias = "Elixir." + instance.moduleName;
  // moduleProxy(alias) resolves globalThis[moduleJsName(alias)] — a BARE
  // name would land in the Erlang_* namespace and read as "not registered".
  const moduleProxy = I.moduleProxy(moduleAlias);

  if (!moduleProxy) {
    throw new Error(
      `[tessera-holo] component ${instance.moduleName} is not registered — ` +
        "load its bundle before mounting",
    );
  }

  const propsWithCid = {...instance.props, cid: instance.cid};

  const propsDom = T.list(
    Object.entries(propsWithCid).map(([name, value]) =>
      T.tuple([
        T.bitstring(name),
        T.keywordList([
          [T.atom("expression"), T.tuple([RT.JsInterop.boxActionParam(value)])],
        ]),
      ]),
    ),
  );

  const dom = T.tuple([T.atom("component"), moduleAlias, propsDom, T.list([])]);

  // renderDom's `context` is the EMITTED-CONTEXT boxed map (stock passes
  // pageEmittedContext from #renderPageInsideLayout) — NOT a buildContext
  // object; renderStatefulComponent feeds it straight into :maps.merge/2.
  // A standalone instance has no context providers, so it starts empty.
  // defaultTarget is overridden by #renderStatefulComponent with the
  // component cid, so template event bindings target this instance.
  const context = T.map();
  const content = R.renderDom(dom, context, T.keywordList([]), T.bitstring("page"), null);

  // renderDom returns a FLAT ARRAY of vnodes/text for a list-root template
  // (#renderNodes). Stock patches a single vnode (renderPage wraps the array
  // in html/body vnodes); snabbdom cannot patch an array — wrap in a div
  // matching the hostDiv selector so patch updates it in place.
  const vnode = Array.isArray(content) ? h("div", {}, content) : content;

  if (!instance.patch) {
    instance.patch = snabbdomInit([attributesModule, eventListenersModule]);
    instance.vnode = instance.patch(toVNode(instance.hostDiv), vnode);
  } else {
    withFocusPreservation(instance, () => {
      instance.vnode = instance.patch(instance.vnode, vnode);
    });
  }
}

function withFocusPreservation(instance, patchFn) {
  const root = instance.shadowRoot;
  const active = root.activeElement || instance.hostDiv.ownerDocument?.activeElement || null;
  const relevant =
    active && active !== instance.hostDiv.ownerDocument?.body && root.contains
      ? root.contains(active) ||
        (instance.element && instance.element.contains(active))
      : false;

  if (!relevant) {
    patchFn();
    return;
  }

  const selectionStart =
    typeof active.selectionStart === "number" ? active.selectionStart : null;
  const selectionEnd = typeof active.selectionEnd === "number" ? active.selectionEnd : null;

  patchFn();

  if (root.activeElement !== active && active.isConnected) {
    try {
      active.focus();

      if (selectionStart !== null && active.setSelectionRange) {
        active.setSelectionRange(selectionStart, selectionEnd ?? selectionStart);
      }
    } catch (_error) {
      /* focus restoration is best-effort */
    }
  }
}

function destroyInstance(instance) {
  try {
    instance.hostDiv.remove();
  } catch (_error) {
    /* already detached */
  }

  // ComponentRegistry has no delete API — mirror its in-place mutation.
  try {
    // eslint-disable-next-line no-unused-expressions
    delete RT.ComponentRegistry.entries.data[
      RT.Type.encodeMapKey(RT.Type.bitstring(instance.cid))
    ];
  } catch (_error) {
    /* entry absent */
  }

  instances.delete(instance.cid);
}

// ---------------------------------------------------------------------------
// public action dispatch / state snapshot (spike item B)
// ---------------------------------------------------------------------------

function dispatchComponentAction(instance, actionName, params) {
  const T = RT.Type;

  // EXTENSION-CONTRACT v0.1: names + param keys accepted in either case;
  // every action is dispatchable (no allowlist).
  const snakeName = normalizeActionName(actionName);

  const action = T.actionStruct({
    name: T.atom(snakeName),
    params: RT.JsInterop.boxActionParam(snakeKeysDeep(params || {})),
    target: T.bitstring(instance.cid),
    delay: T.integer(0),
  });

  return RT.Hologram.executeAction(action);
}

function stateSnapshot(instance) {
  const struct = RT.ComponentRegistry.getComponentStruct(RT.Type.bitstring(instance.cid));

  if (!struct) return null;

  const state = globalThis.Erlang_Maps["get/2"](RT.Type.atom("state"), struct);

  // Primary keys are camelCase (CONTRACT.md §1 wire shapes); snake_case
  // reads also work as aliases (EXTENSION-CONTRACT v0.1) — both are
  // materialized, the whole snapshot deep-frozen.
  return deepFreeze(withSnakeAliases(toJs(state)));
}

function withSnakeAliases(value) {
  if (Array.isArray(value)) return value.map(withSnakeAliases);

  if (value && typeof value === "object") {
    const out = {};

    for (const [k, v] of Object.entries(value)) {
      out[k] = withSnakeAliases(v);

      const snakeKey = camelToSnake(k);

      if (snakeKey !== k && !(snakeKey in out)) out[snakeKey] = out[k];
    }

    return out;
  }

  return value;
}

// ---------------------------------------------------------------------------
// value conversion (CONTRACT.md §1 wire shapes)
// ---------------------------------------------------------------------------

// Boxed Hologram value -> plain JS, map keys camelCased.
export function toJs(value) {
  const T = RT.Type;

  if (T.isNil(value)) return null;
  if (T.isBitstring(value)) return bitstringText(value);
  if (T.isAtom(value)) return value.value;

  switch (value.type) {
    case "integer":
    case "float":
      return Number(value.value);
    case "boolean":
      return value.value;
    case "list":
      return value.data.map(toJs);
    case "map": {
      const out = {};

      for (const [, [k, v]] of Object.entries(value.data)) {
        out[camel(keyText(k))] = toJs(v);
      }

      return out;
    }
    case "tuple":
      return value.data.map(toJs);
    default:
      return null;
  }
}

function keyText(key) {
  return RT.Type.isBitstring(key) ? bitstringText(key) : key.value;
}

export function camel(key) {
  return String(key).replace(/_([a-z0-9])/g, (_, c) => c.toUpperCase());
}

export function snakeToKebab(name) {
  return String(name).replace(/_/g, "-");
}

export function camelToSnake(name) {
  return String(name).replace(/([A-Z])/g, (_, c) => "_" + c.toLowerCase());
}

export function kebabToSnake(name) {
  return String(name).replace(/-/g, "_");
}

// Action names are accepted in snake_case, camelCase or kebab-case
// (EXTENSION-CONTRACT v0.1 §1) — all normalize to the compiled snake_case
// action name.
export function normalizeActionName(name) {
  return camelToSnake(kebabToSnake(String(name)));
}

// Plain JS object (camelCase keys) -> plain JS object (snake_case keys),
// recursively. Arrays preserved.
export function snakeKeysDeep(value) {
  if (Array.isArray(value)) return value.map(snakeKeysDeep);

  if (value && typeof value === "object" && Object.getPrototypeOf(value) === Object.prototype) {
    const out = {};

    for (const [k, v] of Object.entries(value)) {
      out[camelToSnake(k)] = snakeKeysDeep(v);
    }

    return out;
  }

  return value;
}

// Plain JS object (snake_case keys) -> camelCase keys, recursively.
export function camelKeysDeep(value) {
  if (Array.isArray(value)) return value.map(camelKeysDeep);

  if (value && typeof value === "object" && Object.getPrototypeOf(value) === Object.prototype) {
    const out = {};

    for (const [k, v] of Object.entries(value)) {
      out[camel(k)] = camelKeysDeep(v);
    }

    return out;
  }

  return value;
}

function deepFreeze(value) {
  if (value && typeof value === "object" && !Object.isFrozen(value)) {
    Object.freeze(value);
    Object.values(value).forEach(deepFreeze);
  }

  return value;
}
