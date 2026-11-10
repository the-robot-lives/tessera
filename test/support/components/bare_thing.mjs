// Test fixture element for BareThing — stub only.
import { defineOnce, TesseraElement } from "@noizu/tessera-core";
import contract from "./bare_thing.contract.generated.mjs";

class BareThing extends TesseraElement(HTMLElement, contract) {}

export function register() {
  return defineOnce("bare-thing", BareThing);
}
