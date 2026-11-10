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
    ]) {
      expect(core[name], `export "${name}"`).to.exist;
    }
    expect(core.noneTransport.name).to.equal("none");
    expect(core.envelope({ kind: "k", payload: {} }).v).to.equal(1);
  });
});
