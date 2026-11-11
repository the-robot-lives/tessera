# Used by "mix format"
[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  import_deps: [:hologram],
  # The tessera DSL reads as bare keyword calls (attr :name, :type, opts),
  # like Hologram's own prop — keep the formatter from parenthesizing them.
  locals_without_parens: [
    attr: 2,
    attr: 3,
    prop: 2,
    prop: 3,
    event: 1,
    event: 2,
    slot: 1,
    cy: 1
  ]
]
