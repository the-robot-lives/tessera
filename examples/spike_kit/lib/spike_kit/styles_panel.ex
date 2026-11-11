defmodule SpikeKit.StylesPanel do
  @moduledoc """
  `<spike-styles-panel>` — styles-DSL fixture (Tier-1 P0 parity cluster,
  lit-parity §2.5). Exercises every row the DSL closes: author `:host`,
  `:host([attr])`, `:host(.class)`, `::slotted()`, `var(--tsr-<tag>-*)` with
  fallbacks, shared style modules and static array composition (later entries
  win the cascade). The host exposes a `root` part; the template declares
  `row` and `accent` parts — all three are declared in the CEM.

  WTR: `test/components/styles_panel_test.mjs` (S-01…S-06 + X-14).
  """

  use Noizu.Tessera.Component, tag: "spike-styles-panel", js: "spike_styles_panel.mjs"

  attr(:tone, :string, default: "light")

  cy("spike-styles-panel-root")

  # Composition order: shared module, then two author blocks. The second
  # block's .accent color overrides the first's — array order is the cascade.
  styles([
    {:shared, "./shared_styles.mjs"},
    ~CSS"""
    :host {
      display: block;
      padding: var(--tsr-spike-styles-panel-padding, 8px);
      border: 1px solid var(--tsr-spike-styles-panel-accent, #6cf);
    }
    :host([tone="dark"]) {
      background: #111;
    }
    :host(.highlighted) {
      outline: 2px solid var(--tsr-spike-styles-panel-accent, #6cf);
    }
    ::slotted(p) {
      margin: 0;
      color: var(--tsr-spike-styles-panel-slotted, #c0c);
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
      gap: var(--tsr-spike-styles-panel-gap, 4px);
    }
    .accent {
      color: var(--tsr-spike-styles-panel-accent, #6cf);
    }
    """
  ])

  template(~TSR"""
  <div class="row" part="row" data-cy="spike-styles-panel-row">
    <span class="accent" part="accent" data-cy="spike-styles-panel-accent">{@tone}</span>
    <span class="shared-marker" data-cy="spike-styles-panel-shared">shared</span>
    <slot></slot>
  </div>
  """)
end
