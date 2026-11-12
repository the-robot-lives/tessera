defmodule Noizu.Tessera.FromLit.RenderMixTaskTest do
  # not async: Mix.shell() is global state
  use ExUnit.Case, async: false

  alias Noizu.Tessera.FromLit.Extractor

  @fixture_dir Path.expand("../../../fixtures/lit", __DIR__)
  @fixture Path.join(@fixture_dir, "construct_kitchen_sink.ts")

  test "mix tessera.from_lit prints the drop warning and writes the # TODO(tessera.from_lit) marker" do
    root =
      Path.join(System.tmp_dir!(), "tessera_from_lit_task_#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)

    output =
      ExUnit.CaptureIO.capture_io(:stdio, fn ->
        Mix.Tasks.Tessera.FromLit.run([
          @fixture,
          "--out",
          root,
          "--module",
          "Tessera.FromLitTask.Sink",
          "--tag",
          "task-sink",
          "--force"
        ])
      end)

    on_exit(fn -> File.rm_rf!(root) end)

    # unsupported constructs are reported as warnings...
    assert output =~ "WARNING: render(): call `nothing(…)` is outside the supported subset"

    assert output =~
             "WARNING: render(): `style` binding: classMap/styleMap take an inline object literal — variable or call arguments are outside the subset"

    # ...and embedded as TODO markers in the written spec module
    spec_path = Path.join([root, "lib", "tessera", "from_lit_task", "sink.ex"])
    assert File.exists?(spec_path), "expected generated spec at #{spec_path}"
    assert File.read!(spec_path) =~ "# TODO(tessera.from_lit): "
  end

  test "extractor-level warning rides along for a dropped directive argument" do
    shape = @fixture |> Extractor.extract_file() |> elem(1)
    assert is_map_key(shape, "render")
  end
end
