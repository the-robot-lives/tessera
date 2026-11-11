// Shared CSSResult module for the tsr-conf-styles conformance fixture (S-05).
// The sanctioned shared-styles pattern (lit-parity row 92): a plain module
// exporting a `styles` CSSResult, referenced as {:shared, "./shared_styles.mjs"}.
import { css } from "lit";

export const styles = css`
  .shared-marker {
    color: rgb(0, 128, 0);
  }
`;
