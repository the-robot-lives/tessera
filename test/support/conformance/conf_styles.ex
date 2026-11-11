defmodule Tessera.TestFixtures.Conformance.Styles do
  @moduledoc """
  `<tsr-conf-styles>` — conformance fixture for the Tier-1 styles DSL
  (brief 4b case-fill; feature landed via brief 1b).

  Mirrors the spike_kit styles-panel surface: author `:host`, `:host([attr])`,
  `::slotted()`, tag-scoped `var(--tsr-<tag>-*)` reads with fallbacks, a shared
  CSSResult module, and static-array composition (later entries win the
  cascade). The host exposes a `root` part; the template declares `row` and
  `accent` parts.

  Cases: S-01…S-06 (styles) + X-14 (theming — declared parts exist; custom
  properties resolve with fallbacks).
  """

  use Noizu.Tessera.Component, tag: "tsr-conf-styles", js: "conf_styles.mjs"

  attr(:tone, :string, default: "light")

  cy("conf-styles-root")

  # Composition order: shared module, then two author blocks. The second
  # block's .accent color overrides the first's — array order is the cascade.
  styles([
    {:shared, "./shared_styles.mjs"},
    ~CSS"""
    :host {
      display: block;
      padding: var(--tsr-tsr-conf-styles-padding, 8px);
      border: 1px solid var(--tsr-tsr-conf-styles-accent, #6cf);
    }
    :host([tone="dark"]) {
      background: #111;
    }
    ::slotted(p) {
      margin: 0;
      color: var(--tsr-tsr-conf-styles-slotted, #c0c);
    }
    .row {
      display: flex;
    }
    .accent {
      color: #000;
    }
    """,
    ~CSS"""
    .row {
      gap: var(--tsr-tsr-conf-styles-gap, 4px);
    }
    .accent {
      color: var(--tsr-tsr-conf-styles-accent, #6cf);
    }
    """
  ])

  template ~TSR"""
  <div class="row" part="row" data-cy="conf-styles-row">
    <span class="accent" part="accent" data-cy="conf-styles-accent">{@tone}</span>
    <span class="shared-marker" data-cy="conf-styles-shared">shared</span>
    <slot>
  </div>
  """
end