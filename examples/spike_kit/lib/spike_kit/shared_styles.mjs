// Shared style module — the Lit shared-styles pattern (lit-parity row 92 /
// S-05). Hand-written on purpose: the styles DSL's {:shared, "./shared_styles.mjs"}
// entry imports this module's `styles` CSSResult into the generated element's
// static styles array, exactly as a hand-written Lit element would.
import { css } from "lit";

export const styles = css`
  .shared-marker {
    letter-spacing: 0.5px;
    text-transform: uppercase;
  }
`;