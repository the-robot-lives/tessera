defmodule Noizu.Tessera.Component.Styles do
  @moduledoc """
  CSS helpers for the `styles` DSL (EXTENSION-CONTRACT.md §7 theming).

  Pure functions over the recorded CSS text — deliberately NOT a CSS parser
  or linter (Lit validates author CSS at runtime). Only what the theming
  contract needs is extracted:

    * `custom_property_reads/2` — every `var(--tsr-<tag>-*)` read in a CSS
      string, with its fallback (`nil` when absent). Tag-scoped: un-prefixed
      globals and other tags' properties are not this element's contract
      surface and are left alone.
    * `missing_fallbacks/2` — the tag-scoped reads that lack a `var()`
      fallback (the contract requires one so an unthemed element renders).
    * `parts/1` — part names declared in template markup (`part="…"`).
    * `escape_css_template/1` — make CSS text safe inside a Lit `css```
      template literal (backslash, backtick and `${` escaped; the CSS bytes
      are preserved verbatim).

  Known limits (Tier 1, thin by design): `var()` inside CSS strings
  (`content: "var(…)"`) is scanned like real CSS, and shared style modules
  (`{:shared, path}`) are JS-side — their reads are not scanned, so properties
  read only inside a shared module must be declared by the consuming
  component's own `styles` block.
  """

  @prop_segment ~r/^[a-z0-9]+(-[a-z0-9]+)*$/

  @doc """
  Every `var(--tsr-<tag>-*)` read in `css`, as `%{name: name, default:
  fallback_or_nil}` — sorted by name, first occurrence wins on duplicates.
  Nested `var()` fallbacks are reported as their own reads too. Raises
  `ArgumentError` on an unbalanced `var(`.
  """
  @spec custom_property_reads(String.t(), String.t()) :: [
          %{name: String.t(), default: String.t() | nil}
        ]
  def custom_property_reads(css, tag) when is_binary(css) and is_binary(tag) do
    prefix = "--tsr-" <> tag <> "-"

    css
    |> strip_comments()
    |> var_reads()
    |> Enum.flat_map(fn args ->
      {name, fallback} = split_first_arg(args)

      if String.starts_with?(name, prefix) and
           Regex.match?(@prop_segment, String.replace_prefix(name, prefix, "")) do
        [%{name: name, default: fallback}]
      else
        []
      end
    end)
    |> Enum.uniq_by(& &1.name)
    |> Enum.sort_by(& &1.name)
  end

  @doc "Names of the tag-scoped `var()` reads in `css` that carry no fallback."
  @spec missing_fallbacks(String.t(), String.t()) :: [String.t()]
  def missing_fallbacks(css, tag) when is_binary(css) and is_binary(tag) do
    css
    |> custom_property_reads(tag)
    |> Enum.filter(&is_nil(&1.default))
    |> Enum.map(& &1.name)
  end

  @doc """
  Part names declared in template markup via `part="…"` / `part='…'`
  (space-separated lists split), in first-appearance order, deduplicated.
  `exportparts` and `data-part` are NOT part declarations.
  """
  @spec parts(String.t() | nil) :: [String.t()]
  def parts(nil), do: []

  def parts(markup) when is_binary(markup) do
    ~r/(?<![\w-])part\s*=\s*(["'])(.*?)\1/s
    |> Regex.scan(markup)
    |> Enum.flat_map(fn [_full, _quote, names] -> String.split(names, ~r/\s+/, trim: true) end)
    |> Enum.uniq()
  end

  @doc """
  Escape CSS text for inclusion in a Lit `css``` template literal: a raw
  backtick would close the literal and a raw `${` would open a JS
  interpolation — both are injection/corruption hazards in author CSS.
  Backslash is escaped first so the escapes themselves are not re-escaped.
  """
  @spec escape_css_template(String.t()) :: String.t()
  def escape_css_template(css) when is_binary(css) do
    css
    |> String.replace("\\", "\\\\")
    |> String.replace("`", "\\`")
    |> String.replace("${", "\\${")
  end

  # -- internals ---------------------------------------------------------------

  defp strip_comments(css), do: Regex.replace(~r"/\*.*?\*/"s, css, "")

  # Every `var(` occurrence (not `myvar(` / `--var(`), args extracted with a
  # balanced-paren walk so nested var()/rgba() fallbacks survive intact.
  defp var_reads(css) do
    ~r/(?<![\w-])var\(/
    |> Regex.scan(css, return: :index)
    |> Enum.map(fn [{start, len}] -> balanced_args(css, start + len) end)
  end

  defp balanced_args(css, from) do
    binary_part(css, from, byte_size(css) - from) |> walk_args(1, [])
  end

  defp walk_args(<<>>, _depth, _acc),
    do: raise(ArgumentError, "unbalanced var(...) in tessera styles")

  defp walk_args(<<")", _rest::binary>>, 1, acc),
    do: acc |> Enum.reverse() |> IO.iodata_to_binary()

  defp walk_args(<<"(", rest::binary>>, depth, acc),
    do: walk_args(rest, depth + 1, ["(" | acc])

  defp walk_args(<<")", rest::binary>>, depth, acc),
    do: walk_args(rest, depth - 1, [")" | acc])

  defp walk_args(<<c::utf8, rest::binary>>, depth, acc),
    do: walk_args(rest, depth, [<<c::utf8>> | acc])

  # Split the argument list at the FIRST top-level comma: name | fallback.
  defp split_first_arg(args) do
    case split_comma(args, 0, []) do
      {name, rest} -> {String.trim(name), String.trim(rest)}
      :no_comma -> {String.trim(args), nil}
    end
  end

  defp split_comma(<<>>, _depth, _acc), do: :no_comma

  defp split_comma(<<",", rest::binary>>, 0, acc),
    do: {acc |> Enum.reverse() |> IO.iodata_to_binary(), rest}

  defp split_comma(<<"(", rest::binary>>, depth, acc),
    do: split_comma(rest, depth + 1, ["(" | acc])

  defp split_comma(<<")", rest::binary>>, depth, acc),
    do: split_comma(rest, depth - 1, [")" | acc])

  defp split_comma(<<c::utf8, rest::binary>>, depth, acc),
    do: split_comma(rest, depth, [<<c::utf8>> | acc])
end
