/**
 * Universal-bus SEAM (phase 1; transports land in phase 2).
 *
 * Source: tobor-kit `docs/universal-bus-for-web-components.md` §5. Every
 * outbound feed carries the envelope `{v, kind, site, component, ts,
 * idempotency_key, payload}`; a feed/provider rejects rather than guesses a
 * poisoned shape, and a component with no backend degrades rather than
 * throws. Phase 1 therefore ships only the client seam: an injected
 * transport, with a default `none` transport that resolves every capability
 * to `{ok: false, reason: "no-transport"}`.
 */

/** Result every method resolves to when no capable transport is installed. */
const NO_TRANSPORT = Object.freeze({ ok: false, reason: "no-transport" });

let busSeq = 0;

function makeIdempotencyKey() {
  const uuid = globalThis.crypto?.randomUUID?.();
  if (uuid) return uuid;
  // Non-crypto fallback (old runtimes / insecure contexts): uniqueness is
  // best-effort until a real transport owns retries.
  return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}-${(busSeq++).toString(36)}`;
}

/**
 * Build the §5 envelope.
 *
 * @param {{ kind: string, site?: string, component?: string, payload: object }} input
 * @returns {{ v: number, kind: string, site: string, component: string,
 *   ts: number, idempotency_key: string, payload: object }}
 */
export function envelope({ kind, site, component, payload }) {
  return {
    v: 1,
    kind,
    site: site ?? "",
    component: component ?? "",
    ts: Date.now(),
    idempotency_key: makeIdempotencyKey(),
    payload,
  };
}

/**
 * The default transport: no backend capability at all. Never throws.
 */
export const noneTransport = Object.freeze({
  name: "none",
  /** @returns {Promise<{ok: boolean, reason?: string}>} */
  send: async () => ({ ...NO_TRANSPORT }),
});

/**
 * Bus client seam. `kv`, `pubsub`, `me`, `notify` and `upload` each send one
 * §5 envelope through the injected transport and always RESOLVE — a missing
 * capability is `{ok: false, reason: "no-transport"}`, a throwing transport
 * is `{ok: false, reason: "transport-error"}`, never a rejection.
 *
 * A transport is `{ name?: string, send(kind: string, envelope: object): Promise<any> }`;
 * phase 2 adds the Hologram transport (`tsr-bus-request` → layout action).
 */
export class BusClient {
  #transport;
  #site;
  #component;

  /**
   * @param {{ transport?: { name?: string, send: Function }, site?: string,
   *   component?: string }} [options]
   */
  constructor({ transport, site, component } = {}) {
    this.#transport = transport ?? noneTransport;
    this.#site = site ?? "";
    this.#component = component ?? "";
  }

  get transportName() {
    return this.#transport?.name ?? "none";
  }

  async kv(payload) {
    return this.#send("kv", payload);
  }

  async pubsub(payload) {
    return this.#send("pubsub", payload);
  }

  async me(payload) {
    return this.#send("me", payload);
  }

  async notify(payload) {
    return this.#send("notify", payload);
  }

  async upload(payload) {
    return this.#send("upload", payload);
  }

  async #send(kind, payload) {
    const message = envelope({ kind, site: this.#site, component: this.#component, payload: payload ?? {} });
    const send = this.#transport?.send;
    if (typeof send !== "function") return { ...NO_TRANSPORT };
    try {
      const result = await send.call(this.#transport, kind, message);
      // A transport that answers nothing usable counts as no capability.
      if (result === null || result === undefined || typeof result !== "object") return { ...NO_TRANSPORT };
      return result;
    } catch (err) {
      console.warn(`[tessera] bus transport "${this.transportName}" failed for kind "${kind}": ${err?.message ?? err}`);
      return { ok: false, reason: "transport-error" };
    }
  }
}
