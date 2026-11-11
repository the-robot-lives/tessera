// Shared fixtures + helpers for the @noizu/tessera-core WTR suite.
//
// One module so the FAST group (core element/bridge/behaviors tests) and the
// FULL group (per-host Lit matrix + cross-module-copy redundancy) assert
// against the SAME contract and helpers. Not a test file (no `.test.mjs`
// suffix), so WTR never picks it up as a suite. See docs/notes/test-tiering.md.

export const PLAIN_TAG = "tsr-el-plain";
export const LIT_TAG = "tsr-el-lit";

export const plainContract = {
  version: 1,
  tag: PLAIN_TAG,
  attrs: [
    { name: "display-name", key: "displayName", type: "string", required: true, default: null },
    { name: "count", key: "count", type: "integer", default: 0 },
    { name: "ratio", key: "ratio", type: "float" },
    { name: "active", key: "active", type: "boolean" },
  ],
  props: [{ name: "tagList", type: "list", json: true, default: [] }],
  events: [{ name: "plain-select", detail: { personaId: "string" } }],
  slots: ["default"],
  cy: "plain-el-root",
};

export function captureWarns(fn) {
  const warns = [];
  const original = console.warn;
  console.warn = (msg) => warns.push(String(msg));
  try {
    fn();
  } finally {
    console.warn = original;
  }
  return warns;
}