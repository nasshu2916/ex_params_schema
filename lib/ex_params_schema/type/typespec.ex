defmodule ExParamsSchema.Type.Typespec do
  @moduledoc false

  @spec resolve(module()) :: Macro.t()
  def resolve(module) do
    cond do
      typespec_callback?(module) -> module.typespec()
      struct_module?(module) and type_defined?(module, :t) -> {{:., [], [module, :t]}, [], []}
      true -> quote(do: dynamic())
    end
  end

  @spec typespec(module()) :: Macro.t()
  def typespec(module), do: resolve(module)

  @spec typespec_callback?(module()) :: boolean()
  defp typespec_callback?(module), do: Code.ensure_loaded?(module) and function_exported?(module, :typespec, 0)

  @spec struct_module?(module()) :: boolean()
  defp struct_module?(module), do: Code.ensure_loaded?(module) and function_exported?(module, :__struct__, 0)

  @spec type_defined?(module(), atom()) :: boolean()
  defp type_defined?(module, name) do
    case Code.Typespec.fetch_types(module) do
      {:ok, types} ->
        Enum.any?(types, fn
          {kind, {^name, _type, _arguments}} when kind in [:type, :opaque] -> true
          _ -> false
        end)

      :error ->
        false
    end
  end
end
