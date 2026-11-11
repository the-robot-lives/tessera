defmodule Tessera.TestFixtures.SpikeWidgetSpec do
  @moduledoc """
  The hand-built spec behind `test/fixtures/spike_widget.element.golden.mjs`.

  Shared by `Noizu.Tessera.Component.LitCodegenTest` (byte-identity + fragment
  tests) and `mix tessera.golden` (reviewed regeneration) so the golden and
  the tests can never drift apart. The module/file fields are deliberately
  synthetic — the golden pins them as the "Source of truth" line.
  """

  alias Noizu.Tessera.Spec

  @spec spec() :: Spec.t()
  def spec do
    %Spec{
      version: 1,
      tag: "spike-widget",
      module: Noizu.Tessera.Component.LitCodegenTest.SpikeWidget,
      file: "lib/spike_widget.ex",
      js: "spike_widget.mjs",
      cy: "spike-widget-root",
      attrs: [%{name: :label, type: :string, default: "Count", line: 2}],
      props: [%{name: :items, type: :list, line: 7}],
      slots: [],
      events: [%{name: "count-change", detail: %{count: :integer}, line: 4}],
      state: [%{name: :count, type: :integer, default: 0, line: 3}],
      actions: [
        %{
          name: :increment,
          js: ~S|(() => { return ({ ...state, count: (state.count + 1) }); })()|,
          line: 5
        }
      ],
      template: %{
        lexer: :minimal,
        raw: "<div>{@count}</div>",
        render_js: "html`<div>${__t(this.count)}</div>`",
        line: 6
      }
    }
  end
end
