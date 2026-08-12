defmodule ExParamsSchema.Definition.Typespec do
  @moduledoc """
  Builds the typespec AST for generated structs from normalized fields.

  This internal module is used by `ExParamsSchema.Compiler` at compile time.
  """

  alias ExParamsSchema.Definition.Field

  @doc """
  フィールド定義から構造体の型仕様 AST を返します。

      iex> fields = [
      ...>   %ExParamsSchema.Definition.Field{name: :count, type: :integer},
      ...>   %ExParamsSchema.Definition.Field{name: :label, type: :string, options: [optional: true]}
      ...> ]
      iex> ast = ExParamsSchema.Definition.Typespec.struct_type(fields)
      iex> Macro.to_string(ast)
      "%__MODULE__{count: integer(), label: String.t() | nil}"
  """
  @spec struct_type([Field.t()]) :: Macro.t()
  def struct_type(fields) do
    fields
    |> Enum.map(fn field -> {field.name, type_ast(field.type, field.options)} end)
    |> then(&{:%, [], [{:__MODULE__, [], Elixir}, {:%{}, [], &1}]})
  end

  @spec type_ast(Field.normalized_type(), ExParamsSchema.field_options()) :: Macro.t()
  defp type_ast(:any, options), do: nullable_ast(quote(do: dynamic()), options)
  defp type_ast(:boolean, options), do: nullable_ast(quote(do: boolean()), options)
  defp type_ast(:date, options), do: nullable_ast(quote(do: Date.t()), options)
  defp type_ast(:datetime, options), do: nullable_ast(quote(do: DateTime.t()), options)
  defp type_ast(:float, options), do: nullable_ast(quote(do: float()), options)
  defp type_ast(:integer, options), do: nullable_ast(quote(do: integer()), options)
  defp type_ast(:null, _options), do: nil
  defp type_ast(:number, options), do: nullable_ast(quote(do: number()), options)
  defp type_ast(:string, options), do: nullable_ast(quote(do: String.t()), options)

  defp type_ast({:enum, allowed}, options) do
    allowed
    |> Enum.reduce(&{:|, [], [&1, &2]})
    |> nullable_ast(options)
  end

  defp type_ast({:custom, module, _options}, options) do
    custom_type_ast(module)
    |> nullable_ast(options)
  end

  defp type_ast({:array, item_type, item_options}, options) do
    type_ast(item_type, item_options)
    |> list_type_ast(options)
    |> nullable_ast(options)
  end

  defp type_ast({:object, fields}, options) do
    fields =
      Enum.map(fields, fn field ->
        {field.name, type_ast(field.type, field.options)}
      end)

    nullable_ast({:%{}, [], fields}, options)
  end

  @spec nullable_ast(Macro.t(), ExParamsSchema.field_options()) :: Macro.t()
  defp nullable_ast(type, options) do
    if Keyword.get(options, :nullable, false) or Keyword.get(options, :optional, false) do
      {:|, [], [type, nil]}
    else
      type
    end
  end

  @spec list_type_ast(Macro.t(), ExParamsSchema.field_options()) :: Macro.t()
  defp list_type_ast(item_type, options) do
    if Keyword.get(options, :min_items, 0) >= 1 do
      [item_type, {:..., [], []}]
    else
      [item_type]
    end
  end

  @spec custom_type_ast(module()) :: Macro.t()
  defp custom_type_ast(module) do
    ExParamsSchema.Type.typespec(module)
  end
end
