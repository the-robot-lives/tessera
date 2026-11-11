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

// Pre-mount / post-destroy `el.state`: the frozen EMPTY snapshot — never null
// (EXTENSION-CONTRACT §6.1 instance surface is total).
export const EMPTY_SNAPSHOT = Object.freeze({});

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

    // A dispatchAction wrapper (when this call came from page JS) installs a
    // per-instance context so the pipeline outcome (commit / veto / stale-drop
    // / throw) can be wrapped into a DispatchResult — EXTENSION-CONTRACT §6.3.
    // Internal invocations ($click bindings) run with ctx === null: their
    // errors are caught + warned here, never rethrown (§6.4).
    const instance =
      !T.isNil(target) && T.isBitstring(target) ? instances.get(bitstringText(target)) : null;
    const ctx = instance ? instance.__dispatch || null : null;

    // 2. per-instance onAction hooks (spike item B, element-owned chain —
    //    survives disconnect/reconnect, EXTENSION-CONTRACT §6.4). Action names
    //    are accepted in snake/camel/kebab case (EXTENSION-CONTRACT v0.1); all
    //    actions are open — no allowlist. Multiple hooks on the same action
    //    compose in registration order — FIRST-registered OUTERMOST (onion,
    //    D3); skipping next() vetoes the action.
    if (instance) {
      const name = Maps["get/2"](T.atom("name"), action).value;
      const chain = instance.hooks.get(normalizeActionName(name));

      if (chain && chain.length > 0) {
        const params = toJs(Maps["get/2"](T.atom("params"), action));

        const runFrom = (index, currentParams) => {
          if (index >= chain.length) {
            // Stale-resolution drop: an async stage that called next() after
            // the element disconnected applies NO state and emits NOTHING —
            // the dispatch wrapper maps this to {ok:false, reason:"vetoed"}
            // (U6, §6.4).
            if (!instances.has(instance.cid)) {
              if (ctx) ctx.stale = true;
              return undefined;
            }

            if (ctx) ctx.ranTerminal = true;

            const rebuilt = T.actionStruct({
              name: T.atom(name),
              params: RT.JsInterop.boxActionParam(snakeKeysDeep(currentParams)),
              target: target,
              delay: Maps["get/3"](T.atom("delay"), action, T.integer(0)),
            });

            openCommit(instance, name);

            try {
              return runOriginal(original, rebuilt);
            } catch (error) {
              consumeCommit(instance);
              throw error; // outer stage try classifies (ctx) / warns (internal)
            }
          }

          // Overrides reach downstream stages projected to camelCase (§6.4
          // params flow); snakeKeysDeep at the terminal re-normalizes for
          // Elixir. camelKeysDeep is idempotent on already-camel keys.
          const next = (replacement) =>
            runFrom(
              index + 1,
              replacement === undefined ? currentParams : camelKeysDeep(replacement),
            );

          try {
            return chain[index](currentParams, next);
          } catch (error) {
            if (ctx) throw error; // dispatch wrapper classifies + shapes + emits
            // Internal invocation: a stage that throws surfaces as
            // tsr-action-error and skips downstream (§6.4), never escapes.
            emitActionError(instance, normalizeActionName(name), error);
            return undefined;
          }
        };

        return runFrom(0, params);
      }
    }

    // No chain — the stock interpreter runs the action. Register the terminal
    // for the dispatch wrapper (a no-hook dispatch is a commit when it runs).
    if (ctx) ctx.ranTerminal = true;
    if (instance) openCommit(instance, Maps["get/2"](T.atom("name"), action).value);

    try {
      return runOriginal(original, action);
    } catch (error) {
      if (instance) consumeCommit(instance);
      if (ctx) throw error; // dispatch wrapper classifies (unknown-action vs error)
      if (instance) emitActionError(instance, Maps["get/2"](T.atom("name"), action).value, error);
      return undefined;
    }
  };
}

// §6.2 Tier-2 commit context — opened exactly when the TERMINAL action runs
// (a veto or a pre-terminal throw never reaches it). The render that follows
// the action carries the snake-canonical action name into the
// `tsr-state-change` detail AND turns a zero-change commit into its exactly
// one `keys: []` event (X-06 "a transition that changed nothing still
// fires"); renders without an open commit only fire on a real key change,
// so prop-update renders stay silent like they are on Tier 1. A throw
// CONSUMES the context so a failed action can never label a later render.
function openCommit(instance, name) {
  instance.__commit = {action: normalizeActionName(String(name)), fired: false};
}

function consumeCommit(instance) {
  if (instance.__commit && !instance.__commit.fired) instance.__commit = null;
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
    // Element-owned hook map when mounting through TesseraHoloElement —
    // registrations survive disconnect/reconnect and work pre-mount
    // (EXTENSION-CONTRACT §6.4). Fallback Map for bare mountComponent users.
    hooks: options.hooks || new Map(),
    // tsr-state-change baseline: null until the FIRST render seeds it —
    // mounting is not a transition, so it must never fire an event.
    lastSnapshot: null,
    // Active DispatchResult context (set only by dispatchComponentAction).
    __dispatch: null,
    // --- brief 3c: lifecycle projection + awaitable updateComplete -------
    // true WHILE renderInstance runs (the only moment a fence can be queued —
    // Tier-2 commits render synchronously inside dispatch/setProps/Hologram.
    // render, exactly as §6.2 pins); waiters resolve when that render ends.
    rendering: false,
    renderWaiters: [],
    // per-mount render counter (firstUpdated additionally latches on the
    // ELEMENT so it fires once per element lifetime — Lit parity, rows
    // #10/#18 of lit-parity §2.1).
    hasRendered: false,
    // merged camelCase props+state view captured at the END of each render;
    // the next render diffs against it to build `changed` (OLD values, plain
    // object — LC-01/LC-04, contract §6.2 camelCase keys).
    lastRenderedView: null,
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
    // brief 3c — awaitable render fence (lit-parity §2.1 rows #12/#220):
    // resolves true when the render cycle observed at access time commits.
    // Tier-2 commits render SYNCHRONOUSLY (Hologram.render → renderInstance
    // inside dispatchAction/setProps), so at idle the DOM is already current
    // and the promise resolves on the next microtask. Accessed DURING a
    // render (from a lifecycle hook) it queues behind that render's commit.
    // Limitation, pinned honestly (same class as the X-10 async-action debt):
    // a render scheduled by Hologram's own async continuation AFTER the
    // dispatch promise settles is not observable from the shim — await the
    // dispatchAction Promise first, then updateComplete.
    updateComplete() {
      return updateCompleteFor(instance);
    },
    hasRendered() {
      return instance.hasRendered;
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


  const prevState = instance.lastSnapshot;

  // --- brief 3c: pre-patch lifecycle projection ---------------------------
  // On the FIRST render the component struct does not exist yet (renderDom
  // registers it inside the patch), so state keys are NOT observable
  // pre-patch — willUpdate's `changed` there carries the props view only.
  // Honest Tier-2 divergence, documented in the LC case header + lit-parity
  // §2.1 row #7. From the second render on, the action has already committed
  // state before this render runs, so willUpdate sees props+state diffs.
  const preView = renderView(instance.props, instance.hasRendered ? stateSnapshot(instance) : null);
  const willChanged = diffView(instance.lastRenderedView, preView);

  instance.rendering = true;
  let committed = false;

  try {
    runElementHook(instance.element, "willUpdate", willChanged);

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

    committed = true;

    const snap = stateSnapshot(instance);

    // --- post-patch: firstUpdated (once per element lifetime) + updated ---
    const postView = renderView(instance.props, snap);
    const changed = diffView(instance.lastRenderedView, postView);
    const firstEver =
      !instance.hasRendered && !(instance.element && instance.element.__tesseraEverRendered);

    if (instance.element) {
      if (firstEver) runElementHook(instance.element, "firstUpdated", changed);
      runElementHook(instance.element, "updated", changed);
      instance.element.__tesseraEverRendered = true;
    }

    instance.hasRendered = true;
    instance.lastRenderedView = postView;

  // tsr-state-change commit point (EXTENSION-CONTRACT §6.2, Tier-2 spike
  // resolution): fired AFTER the re-render, once per transition, with the
  // camelCase keys the transition changed and the post-transition snapshot.
  // An OPEN commit context (a dispatched/template action just ran its
  // terminal) fires even when nothing changed — exactly one event, keys: [],
  // detail.action = the snake-canonical name; renders without one fire only
  // on a real change (prop updates are not transitions). The first render
  // only seeds the baseline (mount is not a transition); disconnected
  // instances never fire it. Not bridge traffic — it is a direct element
  // event and MUST NOT be routed through data-tsr-on.
    if (snap) {
      instance.lastSnapshot = snap;

      if (prevState) {
        const keys = changedKeys(prevState, snap);
        const commit = instance.__commit && !instance.__commit.fired ? instance.__commit : null;

        if ((keys.length > 0 || commit) && instance.element && instance.element.isConnected) {
          if (commit) {
            commit.fired = true;
            instance.__commit = null;
          }

          const detail = {keys, state: snap};

          if (commit) detail.action = commit.action;

          instance.element.dispatchEvent(
            new CustomEvent("tsr-state-change", {
              bubbles: true,
              composed: true,
              detail,
            }),
          );
        }
      }
    }
  } finally {
    // updateComplete fence: whoever queued during this render resolves once
    // the DOM is committed (true) — or with false when the patch itself
    // threw, so a failed render can never hang an awaiting test.
    instance.rendering = false;
    flushRenderWaiters(instance, committed);
  }
}

// ---------------------------------------------------------------------------
// brief 3c — lifecycle projection helpers (hooks + render fence)
// ---------------------------------------------------------------------------

// Merged camelCase view of what a render consumes: props (snake attrs ->
// camel, CONTRACT §1) unioned with the state snapshot (already camel-canonical
// per §6.2; non-enumerable snake aliases are skipped by Object.keys). On
// collision STATE wins — the snapshot is the post-transition value actually
// rendered, props are pre-init inputs.
function renderView(props, snapshot) {
  const view = {};

  for (const [k, v] of Object.entries(props || {})) view[camel(k)] = v;
  if (snapshot) for (const k of Object.keys(snapshot)) view[k] = snapshot[k];

  return view;
}

// changedProperties equivalent — PLAIN object mapping each changed key to its
// OLD value (undefined when the key is new). Strict !== (same basis as
// changedKeys / X-05 reference stability). NOT a live Map — lc_lifecycle.mjs
// LC-04 pins the shape; lit-parity §2.1 row #34. prev === null (first render)
// means every key is new.
function diffView(prev, next) {
  const p = prev || {};
  const changed = {};

  for (const k of Object.keys(next)) {
    if (!(k in p) || p[k] !== next[k]) changed[k] = p[k];
  }

  for (const k of Object.keys(p)) {
    if (!(k in next)) changed[k] = p[k];
  }

  return changed;
}

function updateCompleteFor(instance) {
  if (instance.rendering) {
    // Reentrant access (from a lifecycle hook, or a nested render): queue
    // behind this render's commit instead of resolving on stale DOM.
    return new Promise((resolve) => instance.renderWaiters.push(resolve));
  }

  // Idle: every Tier-2 commit renders synchronously, so the DOM already
  // reflects all state applied before this access. Resolve on the next
  // microtask (lit-parity rows #12/#220).
  return Promise.resolve(true);
}

function flushRenderWaiters(instance, value) {
  if (instance.renderWaiters.length === 0) return;

  const waiters = instance.renderWaiters;
  instance.renderWaiters = [];
  for (const resolve of waiters) resolve(value);
}

// Element-side lifecycle hook dispatch. TIER-2 DIVERGENCE from Lit (which
// propagates): renderInstance also IS the shared Hologram.render loop over
// every mounted instance — a hook that throws must not abort the OTHER
// components' renders, so errors are caught + warned (behaviors/§10 error-
// isolation precedent) and the update completes.
function runElementHook(element, name, arg) {
  if (!element || typeof element[name] !== "function") return;

  try {
    element[name](arg);
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error(
      `[tessera-holo] <${String(element.tagName).toLowerCase()}> ${name}() threw — render continues`,
      error,
    );
  }
}

// Top-level keys whose value changed (added / removed / !==). Snapshot keys
// are canonical camelCase (§6.2), so `keys` is camelCase by construction.
function changedKeys(prev, next) {
  const keys = [];

  for (const k of Object.keys(next)) {
    if (!(k in prev) || prev[k] !== next[k]) keys.push(k);
  }

  for (const k of Object.keys(prev)) {
    if (!(k in next)) keys.push(k);
  }

  return keys;
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
  // brief 3c: a disconnect must never leave an awaiting updateComplete
  // hanging — queue-flush with the "cycle aborted" answer (false).
  flushRenderWaiters(instance, false);

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

  // EXTENSION-CONTRACT v0.1 §6.3: names + param keys accepted in either case;
  // every declared action is dispatchable (D2 — no allowlist). Only UNKNOWN
  // names are rejected, synchronously-shaped: {ok:false, reason}.
  const snakeName = normalizeActionName(actionName);

  const clean = sanitizeDispatchParams(params || {});

  if (clean.rejected) {
    // Function-valued params are rejected before the pipeline runs (§6.3) —
    // a dev warn AND the §6.4 error surface (tsr-action-error), identical to
    // Tier 1's normalizeParams rejection path (X-20).
    // eslint-disable-next-line no-console
    console.warn(
      `[tessera-holo] dispatchAction('${snakeName}'): function-valued params are rejected`,
    );

    emitActionError(instance, snakeName, new Error(
      "tessera: action params must be data-only (function values are rejected)",
    ));

    return {ok: false, reason: "error"};
  }

  const action = T.actionStruct({
    name: T.atom(snakeName),
    params: RT.JsInterop.boxActionParam(snakeKeysDeep(clean.value)),
    target: T.bitstring(instance.cid),
    delay: T.integer(0),
  });

  const ctx = {ranTerminal: false, stale: false};
  instance.__dispatch = ctx;

  const fail = (error) => {
    instance.__dispatch = null;

    if (isUnknownActionError(error)) {
      // §6.3/D2: unknown name — dev-mode warn, no state change, NO event,
      // no throw. (Pinned for this runtime by the Tier-2 e2e "unknown action"
      // case + conformance X-07.)
      // eslint-disable-next-line no-console
      console.warn(
        `[tessera-holo] dispatchAction: unknown action '${snakeName}' on ${instance.moduleName}`,
      );

      return {ok: false, reason: "unknown-action"};
    }

    emitActionError(instance, snakeName, error);

    return {ok: false, reason: "error"};
  };

  const settle = (terminalReturn) => {
    instance.__dispatch = null;

    // Stale-resolution drop: an async stage that applied nothing after
    // disconnect reports as vetoed (U6 — no new enum value), NO value.
    if (ctx.stale) return {ok: false, reason: "vetoed"};

    // VETO (§6.4, U1): a stage returned without calling next — the vetoing
    // stage's return value becomes the DispatchResult value. terminalReturn
    // is the stage's return (sync) or the chain's resolution (async).
    if (!ctx.ranTerminal) return {ok: false, reason: "vetoed", value: terminalReturn};

    // U1: value = the post-transition snapshot (fresh per §6.2).
    return {ok: true, value: stateSnapshot(instance) || EMPTY_SNAPSHOT};
  };

  let result;

  try {
    result = RT.Hologram.executeAction(action);
  } catch (error) {
    return fail(error);
  }

  if (result && typeof result.then === "function") {
    // Any async stage ⇒ Promise<DispatchResult> (§6.3) — callers must treat
    // both shapes. (Limitation mirrors the stock runtime: an Elixir action
    // returning a Promise is processed by Hologram's own .then, which the
    // runtime does not expose; sync actions complete before this resolves.)
    return result.then(settle, fail);
  }

  return settle(result);
}

// Params are untrusted (§6.3, tsr-props reserved-key guard applied to
// dispatch params): `_`-prefixed keys are stripped with a warn, function
// values reject the whole dispatch. Returned value keeps input casing —
// snakeKeysDeep at the pipeline boundary normalizes for Elixir.
function sanitizeDispatchParams(params) {
  let rejected = false;

  const walk = (value) => {
    if (typeof value === "function") {
      rejected = true;
      return undefined;
    }

    if (Array.isArray(value)) return value.map(walk);

    if (value && typeof value === "object" && isPlainObject(value)) {
      const out = {};

      for (const [k, v] of Object.entries(value)) {
        if (k.startsWith("_")) {
          // eslint-disable-next-line no-console
          console.warn(`[tessera-holo] dispatchAction: reserved param key "${k}" stripped`);
          continue;
        }

        out[k] = walk(v);

        if (rejected) return undefined;
      }

      return out;
    }

    return value;
  };

  const value = walk(params);

  return rejected ? {rejected: true} : {rejected: false, value};
}

// Unknown-action detection: Hologram runs the compiled `action/3` clauses;
// a name with no matching clause raises a boxed %FunctionClauseError{}
// (Type.errorStruct: `__struct__` = atom Elixir.FunctionClauseError; the
// message names the MODULE-QUALIFIED mfa — "no function clause matching in
// Elixir.HoloKit.Components.StateProbe.action/3:") thrown as
// HologramBoxedError. Pinned against Hologram 0.10.1 (the clause-error shape)
// by the Tier-2 e2e unknown-action case + conformance X-07 — do not loosen
// without re-pinning.
function isUnknownActionError(error) {
  try {
    const Maps = globalThis.Erlang_Maps;
    const T = RT.Type;
    const boxed = error && error.value;

    if (!boxed || !T.isMap(boxed)) return false;

    const structAlias = Maps["get/2"](T.atom("__struct__"), boxed);

    if (!structAlias || !String(structAlias.value).endsWith("FunctionClauseError")) {
      return false;
    }

    const message = bitstringText(Maps["get/2"](T.atom("message"), boxed));

    return /\baction\/3\b/.test(String(message));
  } catch (_error) {
    return false;
  }
}

function stateSnapshot(instance) {
  const struct = RT.ComponentRegistry.getComponentStruct(RT.Type.bitstring(instance.cid));

  if (!struct) return null;

  const state = globalThis.Erlang_Maps["get/2"](RT.Type.atom("state"), struct);

  return makeSnapshot(state);
}

// EXTENSION-CONTRACT §6.2 (mirrors brief 2a's makeSnapshot): fresh frozen
// snapshot per access. Canonical keys are camelCase (CONTRACT §1 transform of
// the Elixir state keys); snake_case reads are NON-ENUMERABLE own aliases —
// Object.keys / JSON.stringify / spread expose camelCase only. Top-level
// freeze ONLY: nested values are shared references (never deep-frozen — a
// deep freeze here diverged from Tier 1). `_`-prefixed keys are tessera
// internals (§6.8, e.g. the __tessera_host__ bridge slot) and never surface.
//
// The top-level boxed map is walked term-by-term (not rebuilt through toJs):
// an action merge creates a NEW map whose untouched values still reference
// the SAME boxed terms, so nested plain objects are rebuilt once per term
// and cached in a WeakMap — X-05's `s2.meta === s1.meta` and X-06's
// zero-change `keys: []` both depend on that reference identity (Tier 1
// gets it for free from Lit property values).
const nestedPlainCache = new WeakMap();

function snapshotValue(boxed) {
  if (boxed === null || boxed === undefined || typeof boxed !== "object") return toJs(boxed);

  const type = boxed.type;

  if (type === "map" || type === "list" || type === "tuple") {
    let cached = nestedPlainCache.get(boxed);

    if (cached === undefined) {
      cached = toJs(boxed);
      nestedPlainCache.set(boxed, cached);
    }

    return cached;
  }

  return toJs(boxed);
}

function makeSnapshot(boxedState) {
  const snap = {};

  if (boxedState && boxedState.type === "map") {
    for (const [, [k, v]] of Object.entries(boxedState.data || {})) {
      const name = camel(keyText(k));
      if (name.startsWith("_")) continue;
      snap[name] = snapshotValue(v);
    }
  } else {
    const plain = toJs(boxedState); // already camelCases map keys — don't double-convert

    if (plain && typeof plain === "object") {
      for (const [k, v] of Object.entries(plain)) {
        if (k.startsWith("_")) continue;
        snap[k] = v;
      }
    }
  }

  for (const k of Object.keys(snap)) {
    const snake = camelToSnake(k);

    if (snake !== k && !(snake in snap)) {
      Object.defineProperty(snap, snake, {
        value: snap[k],
        enumerable: false,
        writable: false,
        configurable: false,
      });
    }
  }

  return Object.freeze(snap);
}

// tsr-action-error — composed + bubbling on the element (§6.4):
// detail: {action, message, error?}. Never fires for a dropped stale
// resolution or an unknown-action reject.
function emitActionError(instance, name, error) {
  const el = instance && (instance.element || null);
  if (!el || !el.isConnected) return;

  const message =
    (error && typeof error.message === "string" && error.message) || String(error);

  el.dispatchEvent(
    new CustomEvent("tsr-action-error", {
      bubbles: true,
      composed: true,
      detail: {action: name, message, error},
    }),
  );
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

// Realm-neutral plain-object test. A host page's JS and this bundle usually
// share a realm, but test harnesses (Cypress's spec frame driving the AUT)
// hand over objects from ANOTHER realm — `Object.getPrototypeOf(x) ===
// Object.prototype` is then false and params would opaque-box as
// Hologram.JS.NativeValue instead of maps. The prototype chain of a plain
// object ends after ONE hop (proto === null || proto's proto === null);
// class/Date/Map instances take >= 2 hops. JSON-safe param values pass;
// functions/arrays are handled by callers.
function isPlainObject(value) {
  if (value === null || typeof value !== "object") return false;

  const proto = Object.getPrototypeOf(value);

  return proto === null || Object.getPrototypeOf(proto) === null;
}

// Plain JS object (camelCase keys) -> plain JS object (snake_case keys),
// recursively. Arrays preserved.
export function snakeKeysDeep(value) {
  if (Array.isArray(value)) return value.map(snakeKeysDeep);

  if (value && typeof value === "object" && isPlainObject(value)) {
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

  if (value && typeof value === "object" && isPlainObject(value)) {
    const out = {};

    for (const [k, v] of Object.entries(value)) {
      out[camel(k)] = camelKeysDeep(v);
    }

    return out;
  }

  return value;
}

