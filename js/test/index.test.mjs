import { expect } from "@open-wc/testing";
import * as core from "../../priv/js/src/index.mjs";

describe("@noizu/tessera-core index", () => {
  it("re-exports the full public surface", () => {
    for (const name of [
      "defineOnce",
      "emit",
      "snakeKeysDeep",
      "camelKeysDeep",
      "getBridge",
      "registerEvents",
      "parseTsrOn",
      "behaviors",
      "TesseraElement",
      "BusClient",
      "noneTransport",
      "envelope",
      // brief 2a — action pipeline + state snapshot surface
      "snakeCaseKey",
      "camelCaseKey",
      "makeSnapshot",
      "normalizeActionName",
      "normalizeParams",
      "runPipeline",
    ]) {
      expect(core[name], `export "${name}"`).to.exist;
    }
    // pipeline.mjs must stay Lit/DOM-free (docs/notes/test-tiering.md): a
    // pipeline run against plain fakes works outside any element.
    expect(core.runPipeline({ interceptors: [], invoke: () => "v", params: {} }))
      .to.deep.equal({ status: "applied", value: "v" });
    expect(core.noneTransport.name).to.equal("none");
    expect(core.envelope({ kind: "k", payload: {} }).v).to.equal(1);
  });
});
