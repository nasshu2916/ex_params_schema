defmodule ExParamsSchema.Definition.Normalizer do
  @moduledoc false

  alias ExParamsSchema.Definition

  @scalar_types [
    :any,
    :boolean,
    :date,
    :datetime,
    :float,
    :integer,
    :null,
    :number,
    :string
  ]
  @builtin_type_tags [:enum | @scalar_types]

  defguardp is_custom_type_definition(module, options)
            when is_atom(module) and module not in @builtin_type_tags and is_list(options)

  @spec normalize!(ExParamsSchema.definition()) :: Definition.normalized_definition()
  def normalize!({:enum, allowed}) when is_list(allowed) do
    {{:enum, allowed}, []}
  end

  def normalize!({module, custom_options})
      when is_custom_type_definition(module, custom_options) do
    :ok = Definition.Options.validate_custom!(custom_options)
    {{:custom, module, custom_options}, []}
  end

  def normalize!({type, options}) when is_list(options) do
    :ok = Definition.Options.validate!(options)
    {normalize_type!(type), options}
  end

  def normalize!(type) do
    {normalize_type!(type), []}
  end

  @spec fields_from_map!(%{required(atom()) => ExParamsSchema.definition()}) :: [ExParamsSchema.field()]
  def fields_from_map!(schema) when is_map(schema) do
    Enum.map(schema, fn {name, definition} ->
      {type, options} = normalize!(definition)
      {name, type, options}
    end)
  end

  @spec normalize_type!(term()) :: ExParamsSchema.field_type()
  defp normalize_type!({module, custom_options})
       when is_custom_type_definition(module, custom_options) do
    :ok = Definition.Options.validate_custom!(custom_options)
    {:custom, module, custom_options}
  end

  defp normalize_type!(type), do: type
end
