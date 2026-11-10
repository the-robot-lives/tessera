/**
 * Hand-written types for `@noizu/tessera-core` 0.1.x (CONTRACT.md §4).
 * Plain ESM source ships in `src/*.mjs`; these declarations cover every
 * public subpath export.
 */

export type AttrType = "string" | "integer" | "float" | "boolean" | "list" | "map" | "any";

export interface TesseraAttrDef {
  /** kebab-case attribute name, e.g. "display-name" */
  name: string;
  /** camelCase property name, e.g. "displayName" */
  key?: string;
  type: AttrType;
  required?: boolean;
  default?: unknown;
}

export interface TesseraEventDef {
  name: string;
  detail?: Record<string, string>;
}

export interface TesseraContract {
  version: number;
  tag: string;
  attrs?: TesseraAttrDef[];
  props?: Array<{ name: string; type: AttrType; json?: boolean; default?: unknown }>;
  events?: TesseraEventDef[];
  slots?: string[];
  cy?: string;
}

/** Register `ctor` as `tag` once; returns the ctor that owns the tag. */
export function defineOnce(tag: string, ctor: CustomElementConstructor): CustomElementConstructor | undefined;

/** Dispatch a composed, bubbling CustomEvent from `el`. */
export function emit<T>(el: HTMLElement, name: string, detail: T): boolean;

/** Recursively camelCase→snake_case object keys (arrays + plain objects). */
export function snakeKeysDeep<T>(value: T): T;

/** Recursively snake_case→camelCase object keys (arrays + plain objects). */
export function camelKeysDeep<T>(value: T): T;

export interface TsrBinding {
  action: string;
  target: string;
}

/** Parse `data-tsr-on` (`event:action@target;…`) — tolerant, warns on malformed entries. */
export function parseTsrOn(str: string | null | undefined): Map<string, TsrBinding>;

export interface TesseraBridge {
  listeners: Map<string, EventListener>;
  tags: Set<string>;
  behaviors: Map<string, Set<Function>>;
  registerEvents(names: string[], tag?: string): void;
  parseTsrOn(str: string | null | undefined): Map<string, TsrBinding>;
}

/** The `globalThis[Symbol.for("tessera.bridge")]` singleton. */
export function getBridge(): TesseraBridge;

/** Register contract event names (one capture-phase document listener per NEW name). */
export function registerEvents(names: string[], tag?: string): void;

export interface TesseraBehaviors {
  add(tag: string, fn: (el: HTMLElement) => void | (() => void)): void;
  remove(tag: string, fn: (el: HTMLElement) => void | (() => void)): void;
  get(tag: string): Array<(el: HTMLElement) => void | (() => void)>;
}

export const behaviors: TesseraBehaviors;

/** Mixin over `HTMLElement` or `LitElement` driven by a generated contract. */
export function TesseraElement<B extends CustomElementConstructor>(
  Base: B,
  contract: TesseraContract,
): B;

export interface BusEnvelope {
  v: number;
  kind: string;
  site: string;
  component: string;
  ts: number;
  idempotency_key: string;
  payload: Record<string, unknown>;
}

export interface BusResult {
  ok: boolean;
  reason?: string;
  [key: string]: unknown;
}

export interface BusTransport {
  name?: string;
  send(kind: string, envelope: BusEnvelope): Promise<BusResult> | BusResult;
}

export function envelope(input: { kind: string; site?: string; component?: string; payload: Record<string, unknown> }): BusEnvelope;

export const noneTransport: BusTransport;

export class BusClient {
  constructor(options?: { transport?: BusTransport; site?: string; component?: string });
  readonly transportName: string;
  kv(payload?: Record<string, unknown>): Promise<BusResult>;
  pubsub(payload?: Record<string, unknown>): Promise<BusResult>;
  me(payload?: Record<string, unknown>): Promise<BusResult>;
  notify(payload?: Record<string, unknown>): Promise<BusResult>;
  upload(payload?: Record<string, unknown>): Promise<BusResult>;
}
