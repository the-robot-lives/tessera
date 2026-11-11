defmodule Tessera.TestFixtures.DerivedWidgetBase do
  @moduledoc """
  The hand-built BASE spec behind the derived-element golden. Exposes
  `__tessera_spec__/0` so `Noizu.Tessera.Component.LitCodegen` can resolve the
  base class + import path when lowering a derived spec (the same call path a
  real compiled base component uses). Synthetic module/file fields keep the
  golden's "Source of truth" / "Derives from" lines deterministic.
  """

  alias Noizu.Tessera.Spec

  @spec __tessera_spec__() :: Spec.t()
  def __tessera_spec__ do
    %Spec{
      version: 1,
      tag: "widget-base",
      module: __MODULE__,
      file: "lib/widget_base.ex",
      js: "widget_base.mjs",
      attrs: [%{name: :label, type: :string, default: "Count", line: 2}],
      state: [%{name: :count, type: :integer, default: 0, line: 3}],
      events: [%{name: "count-change", detail: %{count: :integer}, line: 4}],
      actions: [
        %{name: :increment, js: "({ ...state, count: (state.count + 1) })", line: 5}
      ],
      styles: [%{kind: :css, value: ":host { color: red; }", line: 6}],
      template: %{
        lexer: :minimal,
        raw: "<div>{@count}</div>",
        render_js: "html`<div>${__t(this.count)}</div>`",
        line: 7
      }
    }
  end
end

defmodule Tessera.TestFixtures.DerivedWidgetSpec do
  @moduledoc """
  The hand-built MERGED spec behind `test/fixtures/derived_widget.element.golden.mjs`.

  Shared by `Noizu.Tessera.Component.LitCodegenTest` (derived lowering shape)
  and `mix tessera.golden` (reviewed regeneration). Inherited entries carry
  `inherited: true` exactly as `Extension.merge_spec!/3` produces them; the
  derived module's own (new/overriding) entries do not. The overridden
  `:increment` action's JS carries the real ES `super` down-call that the
  `base_action/3` special form lowers to.
  """

  alias Noizu.Tessera.Spec

  @spec spec() :: Spec.t()
  def spec do
    %Spec{
      version: 1,
      tag: "derived-widget",
      module: Noizu.Tessera.Component.LitCodegenTest.DerivedWidget,
      file: "lib/derived_widget.ex",
      js: "derived_widget.mjs",
      derived_from: Tessera.TestFixtures.DerivedWidgetBase,
      priority: 0,
      extension_api: "1.0.0",
      attrs: [
        %{name: :label, type: :string, default: "Count", line: 2, inherited: true},
        %{name: :badge, type: :string, default: "", line: 20}
      ],
      state: [
        %{name: :count, type: :integer, default: 0, line: 3, inherited: true},
        %{name: :extra, type: :integer, default: 0, line: 21}
      ],
      events: [
        %{name: "count-change", detail: %{count: :integer}, line: 4, inherited: true},
        %{name: "vendor-ping", detail: %{count: :integer}, line: 22}
      ],
      actions: [
        %{
          name: :increment,
          js:
            "(() => { (state = super.__action_increment(params, ev)); " <>
              "return ({ ...state, extra: (state.extra + 1) }); })()",
          line: 23
        },
        %{name: :bump, js: "({ ...state, extra: (state.extra + 1) })", line: 24}
      ],
      styles: [
        %{kind: :css, value: ":host { color: red; }", line: 6, inherited: true},
        %{kind: :css, value: ":host { border: 1px solid var(--derived-widget-accent, #6cf); }", line: 25}
      ],
      template: %{
        lexer: :minimal,
        raw: "<div>{@badge}{@count}{@extra}</div>",
        render_js: "html`<div>${__t(this.badge)}${__t(this.count)}${__t(this.extra)}</div>`",
        line: 26
      }
    }
  end
end