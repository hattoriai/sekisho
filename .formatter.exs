# Used by "mix format"
locals = [
  permissions: 1,
  role: 2,
  derive: 2,
  relation: 2,
  grant_to: 1,
  grant_to: 2
]

[
  import_deps: [:ecto, :ecto_sql, :phoenix_mountable],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: locals,
  export: [locals_without_parens: locals]
]
