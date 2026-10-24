defmodule Sekisho.Call do
  @moduledoc false
  # An optional callback of yours: nil when it is not defined, or has no
  # clause for these arguments (so a policy or sources module needs no last
  # clause). An error raised further in is raised again.

  def optional(nil, _function, _args), do: nil

  def optional(module, function, args) do
    if Code.ensure_loaded?(module) and function_exported?(module, function, length(args)) do
      apply(module, function, args)
    end
  rescue
    e in FunctionClauseError ->
      if e.module == module and e.function == function and e.arity == length(args),
        do: nil,
        else: reraise(e, __STACKTRACE__)
  end
end
