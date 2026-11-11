defmodule Tessera.TestFixtures.Conformance.RegionVendor do
  @moduledoc """
  `<tsr-conf-region-vendor>` — derived fixture for case X-17 (brief 2d,
  EXTENSION-CONTRACT.md §5.4): replaces `RegionBase`'s `:row` region with a
  `slot_template :row` override that adds vendor chrome, a named `<slot>`
  inside the region body (regions are compiled-in fragments, so slots compose
  normally), and composes the base body via `{%super%}` — which lowers to a
  real ES `super.__region_row()` call on the class chain.

  Same LOGICAL fixture name pair as the tier-agnostic X-17 body: Tier 1
  mounts `regionBase`/`regionVendor`; Tier 2 mirrors land with the HoloKit
  adapter brief.
  """

  use Tessera.TestFixtures.Conformance.RegionBase,
    tag: "tsr-conf-region-vendor",
    js: "conf_region_derived.mjs"

  slot_template(:row, ~TSR"""
  <span class="vendor-row" data-cy="conf-region-vendor"><slot name="row-icon"></slot>{%super%}</span>
  """)
end
