defmodule ExParamsSchema.Definition.Validator do
  @moduledoc false

  alias ExParamsSchema.Definition
  alias ExParamsSchema.Definition.{Field, Normalizer, Validator}

  @scalar_types [:any, :boolean, :date, :datetime, :float, :integer, :null, :number, :string]

  @type duplicate_input_key :: {
          input_key :: Definition.input_key(),
          fields :: [ExParamsSchema.field()]
        }

  @spec normalize_fields!([ExParamsSchema.field()]) :: [ExParamsSchema.field()]
  def normalize_fields!(fields) do
    fields
    |> Enum.map(&normalize_field!/1)
    |> tap(&validate_unique_field_names!/1)
    |> tap(&validate_unique_input_keys!(&1, []))
  end

  @spec validate_definition!(term(), Keyword.t(), Definition.definition_path(), :field | :item) :: :ok
  def validate_definition!({:enum, allowed}, options, path, context) do
    Validator.Options.validate!(options, :atom_enum, path, context)
    validate_atom_enum!(allowed, path)
  end

  def validate_definition!({:custom, module, custom_options}, options, path, context) do
    Validator.Options.validate!(options, :custom, path, context)
    ExParamsSchema.Type.validate_definition!(module, custom_options, path)
  end

  def validate_definition!([item_schema], options, path, context) do
    Validator.Options.validate!(options, :array, path, context)
    {item_type, item_options} = Normalizer.normalize!(item_schema)
    validate_definition!(item_type, item_options, path ++ ["[]"], :item)
  end

  def validate_definition!(schema, options, path, context) when is_map(schema) do
    Validator.Options.validate!(options, :object, path, context)

    fields = validate_nested_fields!(schema, path)
    :ok = validate_unique_input_keys!(fields, path)
  end

  def validate_definition!(type, options, path, context) when type in @scalar_types do
    Validator.Options.validate!(options, type, path, context)
  end

  def validate_definition!(type, _options, path, _context),
    do: raise_definition!(path, "unsupported type #{inspect(type)}")

  @spec validate_unique_field_names!([ExParamsSchema.field()]) :: :ok
  def validate_unique_field_names!(fields) do
    fields_by_name = Enum.group_by(fields, &elem(&1, 0))

    case Enum.find(fields, fn {name, _type, _options} -> length(fields_by_name[name]) > 1 end) do
      nil -> :ok
      {name, _type, _options} -> raise ArgumentError, "schema field name #{inspect(name)} is declared more than once"
    end
  end

  @spec validate_unique_input_keys!([ExParamsSchema.field()], Definition.definition_path()) :: :ok
  def validate_unique_input_keys!(fields, path) do
    fields_by_input_key = Enum.group_by(fields, &input_key/1)

    case Enum.find_value(fields, &duplicate_input_key(&1, fields_by_input_key)) do
      nil ->
        :ok

      {input_key, [{first_name, _, _}, {second_name, _, _} | _fields]} ->
        raise_definition!(
          path,
          "input key #{inspect(input_key)} is used by both fields #{inspect(first_name)} and #{inspect(second_name)}"
        )
    end
  end

  @spec validate_atom_enum!(list(), Definition.definition_path()) :: :ok
  defp validate_atom_enum!(allowed, path) do
    if allowed == [] or not Enum.all?(allowed, &is_atom/1),
      do: raise_definition!(path, "atom enum must contain one or more atoms")

    :ok
  end

  @spec normalize_field!(ExParamsSchema.field()) :: ExParamsSchema.field()
  defp normalize_field!({name, type, options}) when is_atom(name) do
    {type, options} = Normalizer.normalize!({type, options})
    validate_definition!(type, options, [Atom.to_string(name)], :field)
    {name, type, options}
  end

  defp normalize_field!({name, _type, _options}) do
    raise ArgumentError, "schema field name must be an atom, got: #{inspect(name)}"
  end

  @spec duplicate_input_key(ExParamsSchema.field(), map()) :: duplicate_input_key() | nil
  defp duplicate_input_key(field, fields_by_input_key) do
    input_key = input_key(field)

    case fields_by_input_key[input_key] do
      [_field] -> nil
      fields -> {input_key, fields}
    end
  end

  @spec input_key(ExParamsSchema.field()) :: Definition.input_key()
  defp input_key({name, _type, options}), do: Field.input_key(name, options)

  @spec validate_nested_fields!(map(), Definition.definition_path()) :: [ExParamsSchema.field()]
  defp validate_nested_fields!(schema, path) do
    Enum.map(schema, fn {name, definition} ->
      unless is_atom(name), do: raise_definition!(path, "nested field name must be an atom")
      {type, options} = Definition.Normalizer.normalize!(definition)
      validate_definition!(type, options, path ++ [Atom.to_string(name)], :field)
      {name, type, options}
    end)
  end

  @spec raise_definition!(Definition.definition_path(), String.t()) :: no_return()
  defp raise_definition!(path, message) do
    location = if path == [], do: "root", else: Enum.join(path, ".")
    raise ArgumentError, "invalid schema at #{location}: #{message}"
  end
end
