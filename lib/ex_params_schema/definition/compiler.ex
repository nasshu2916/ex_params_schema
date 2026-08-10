defmodule ExParamsSchema.Definition.Compiler do
  @moduledoc false

  alias ExParamsSchema.Definition

  @spec compile_fields!([ExParamsSchema.field()]) :: [Definition.Field.t()]
  def compile_fields!(fields) do
    fields
    |> Definition.Validator.normalize_fields!()
    |> Enum.map(&compile_field/1)
  end

  @spec compile_field(ExParamsSchema.field()) :: Definition.Field.t()
  defp compile_field({name, type, options}) do
    %Definition.Field{
      name: name,
      type: compile_type(type),
      options: options
    }
  end

  @spec compile_type(term()) :: Definition.Field.normalized_type()
  defp compile_type([item_schema]) do
    {type, options} = Definition.Normalizer.normalize!(item_schema)
    {:array, compile_type(type), options}
  end

  defp compile_type(schema) when is_map(schema) do
    {:object, schema |> Definition.Normalizer.fields_from_map!() |> compile_fields!()}
  end

  defp compile_type(type), do: type
end
