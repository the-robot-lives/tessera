defmodule HologramDemo.Web.Hologram.Pages.SpikePage do
  @moduledoc """
  SPIKE (`spike/elixir-to-lit`): the element-DSL components in a Hologram
  host. `<SpikeKit.Counter>`, `<SpikeKit.ToggleChip>` and
  `<SpikeKit.StylesPanel>` are defined entirely in Elixir (`state` /
  `template ~TSR` / `action` / `styles`) and compiled by `mix compile` into
  generated Lit elements — there is no hand-written JS for any of them. The
  Hologram integration is the same js_import + bridge story as persona_kit:
  `chip-select` crosses with camelCase detail keys
  (`chipId`), the `data-tsr-on` bridge snake-cases them back, and
  `on_chip_select={:chose}` lands in the page action with `params.chip_id` —
  the easiest hookup an Elixir author could ask for (docs/notes/spike-elixir-to-lit.md).
  """

  use Hologram.Page

  alias HologramDemo.Web.Hologram.Layouts.RootLayout
  alias SpikeKit.Counter
  alias SpikeKit.StylesPanel
  alias SpikeKit.ToggleChip

  route "/spike"
  layout RootLayout, page_title: "tessera spike — element DSL"

  def init(_params, page, _server) do
    put_state(page,
      chose: "(none)",
      chose_count: 0,
      counted: 0
    )
  end

  # — landing zones: the bridge dispatches here with snake_cased params ——

  def action(:chose, %{chip_id: chip_id, selected: selected}, page) do
    mark = if selected, do: " [on]", else: " [off]"

    put_state(page,
      chose: chip_id <> mark,
      chose_count: page.state.chose_count + 1
    )
  end

  def action(:counted, %{count: count, delta: _delta}, page) do
    put_state(page, counted: count)
  end

  def action(_other, _params, page), do: page

  def template do
    ~HOLO"""
    <h1 data-cy="spike-title">tessera spike — element DSL in Hologram</h1>

    <div class="panel" data-cy="spike-counter-panel">
      <h2>spike-counter → page action (:counted)</h2>
      <p data-cy="spike-counted">page saw count-change: <strong>{@counted}</strong></p>
      <Counter label="Hologram hits" step={1} on_count_change={:counted} />
    </div>

    <div class="panel" data-cy="spike-chips-panel">
      <h2>spike-toggle-chip → page action (:chose, snake_cased params)</h2>
      <p data-cy="spike-chose">page chose: <strong>{@chose}</strong> (<span data-cy="spike-chose-count">{@chose_count}</span>)</p>
      <ToggleChip chip_id="holo-1" label="Ada" on_chip_select={:chose} />
      <ToggleChip chip_id="holo-7" label="Grace" on_chip_select={:chose} />
    </div>

    <div class="panel" data-cy="spike-styles-panel">
      <h2>spike-styles-panel — composed styles + slot (non-void grammar)</h2>
      <StylesPanel tone="dark" />
    </div>
    """
  end
end
