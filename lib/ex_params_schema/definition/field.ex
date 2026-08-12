defmodule ExParamsSchema.Definition.Field do
  @moduledoc """
  An internal struct that represents a normalized field definition.

  It provides field-level common rules such as input keys, optionality, and error reasons.
  """

  @enforce_keys [:name, :type]
  defstruct [
    :name,
    :type,
    options: []
  ]

  @type t :: %__MODULE__{
          name: atom(),
          type: normalized_type(),
          options: ExParamsSchema.field_options()
        }

  @type normalized_enum_type :: {kind :: :enum, allowed_values :: [atom()]}
  @type normalized_custom_type :: {kind :: :custom, module :: module(), options :: keyword()}
  @type normalized_array_type :: {
          kind :: :array,
          item_type :: normalized_type(),
          item_options :: ExParamsSchema.field_options()
        }
  @type normalized_object_type :: {kind :: :object, fields :: [t()]}

  @type normalized_type ::
          ExParamsSchema.scalar_field_type()
          | normalized_enum_type()
          | normalized_custom_type()
          | normalized_array_type()
          | normalized_object_type()

  @doc """
  Returns the key used to fetch a value from an input map.

      iex> ExParamsSchema.Definition.Field.input_key(%ExParamsSchema.Definition.Field{name: :display_name, type: :string})
      "display_name"
      iex> ExParamsSchema.Definition.Field.input_key(%ExParamsSchema.Definition.Field{name: :display_name, type: :string, options: [source: "displayName"]})
      "displayName"
  """
  @spec input_key(t()) :: String.t() | atom()
  def input_key(%__MODULE__{name: name, options: options}), do: input_key(name, options)

  @doc false
  @spec input_key(atom(), ExParamsSchema.field_options()) :: String.t() | atom()
  def input_key(name, options), do: Keyword.get(options, :source, Atom.to_string(name))

  @doc """
  Returns the error reason, preferring field-specific, inherited, then default values.

      iex> field = %ExParamsSchema.Definition.Field{name: :count, type: :integer, options: [error: :invalid_count]}
      iex> ExParamsSchema.Definition.Field.error_reason(field, :invalid_params)
      :invalid_count
      iex> field = %ExParamsSchema.Definition.Field{name: :count, type: :integer}
      iex> ExParamsSchema.Definition.Field.error_reason(field, :invalid_params)
      :invalid_params
      iex> field = %ExParamsSchema.Definition.Field{name: :count, type: :integer}
      iex> ExParamsSchema.Definition.Field.error_reason(field)
      {:invalid_param, :count}
  """
  @spec error_reason(t(), ExParamsSchema.error_reason() | nil) :: ExParamsSchema.error_reason()
  def error_reason(field, inherited_reason \\ nil) do
    Keyword.get(field.options, :error, inherited_reason || {:invalid_param, field.name})
  end

  @doc """
  Returns whether the field is optional.

      iex> ExParamsSchema.Definition.Field.optional?(%ExParamsSchema.Definition.Field{name: :label, type: :string, options: [optional: true]})
      true
      iex> ExParamsSchema.Definition.Field.optional?(%ExParamsSchema.Definition.Field{name: :label, type: :string})
      false
  """
  @spec optional?(t()) :: boolean()
  def optional?(field), do: Keyword.get(field.options, :optional, false)

  @doc """
  Fetches a field value from an input map.

  Prefers the key configured with `source:` and falls back to the field name's atom key when absent.

      iex> field = %ExParamsSchema.Definition.Field{name: :count, type: :integer, options: [source: "input-count"]}
      iex> ExParamsSchema.Definition.Field.fetch_value(%{"input-count" => "1", count: "2"}, field)
      {:ok, "1"}
      iex> field = %ExParamsSchema.Definition.Field{name: :count, type: :integer}
      iex> ExParamsSchema.Definition.Field.fetch_value(%{"count" => "2"}, field)
      {:ok, "2"}
      iex> field = %ExParamsSchema.Definition.Field{name: :count, type: :integer}
      iex> ExParamsSchema.Definition.Field.fetch_value(%{"input-count" => "1"}, field)
      :error
  """
  @spec fetch_value(map(), t()) :: {:ok, ExParamsSchema.value()} | :error
  def fetch_value(params, field) when is_map(params) do
    case Map.fetch(params, input_key(field)) do
      {:ok, value} -> {:ok, value}
      :error -> Map.fetch(params, field.name)
    end
  end

  @doc """
  Returns how to handle a field that has no input value.

  Prefers `default:` when present; otherwise, follows the `optional:` setting.

      iex> field = %ExParamsSchema.Definition.Field{name: :count, type: :integer, options: [default: 0]}
      iex> ExParamsSchema.Definition.Field.missing_value(field)
      {:default, 0}
      iex> field = %ExParamsSchema.Definition.Field{name: :label, type: :string, options: [optional: true]}
      iex> ExParamsSchema.Definition.Field.missing_value(field)
      :optional
      iex> field = %ExParamsSchema.Definition.Field{name: :count, type: :integer}
      iex> ExParamsSchema.Definition.Field.missing_value(field)
      :required
  """
  @spec missing_value(t()) :: {:default, ExParamsSchema.value()} | :optional | :required
  def missing_value(field) do
    case Keyword.fetch(field.options, :default) do
      {:ok, value} -> {:default, value}
      :error -> if optional?(field), do: :optional, else: :required
    end
  end

  @doc """
  Returns whether an input value should be treated as absent for an optional field.

  For strings, whitespace-only values are treated as absent in addition to empty strings.

      iex> field = %ExParamsSchema.Definition.Field{name: :label, type: :string, options: [optional: true]}
      iex> ExParamsSchema.Definition.Field.optional_empty?(field, "  ")
      true
      iex> field = %ExParamsSchema.Definition.Field{name: :label, type: :string}
      iex> ExParamsSchema.Definition.Field.optional_empty?(field, "  ")
      false
  """
  @spec optional_empty?(t(), ExParamsSchema.value()) :: boolean()
  def optional_empty?(field, value) when value in [nil, ""] do
    optional?(field)
  end

  def optional_empty?(%__MODULE__{type: :string} = field, value) when is_binary(value) do
    optional?(field) and String.trim(value) == ""
  end

  def optional_empty?(%__MODULE__{}, _value), do: false

  @doc """
  Returns the first input key that is not included in the field definitions.

  Each field allows both its `source:` key and its field name's atom key.

      iex> fields = [%ExParamsSchema.Definition.Field{name: :count, type: :integer}]
      iex> ExParamsSchema.Definition.Field.unknown_input_key(%{"count" => "1"}, fields)
      nil
      iex> ExParamsSchema.Definition.Field.unknown_input_key(%{"count" => "1", "extra" => "value", "extra2" => "value"}, fields)
      "extra"
      iex> fields = [%ExParamsSchema.Definition.Field{name: :count, type: :integer, options: [source: "input-count"]}]
      iex> ExParamsSchema.Definition.Field.unknown_input_key(%{"input-count" => "1"}, fields)
      nil
  """
  @spec unknown_input_key(map(), [t()]) :: term() | nil
  def unknown_input_key(params, fields) do
    allowed_keys =
      fields
      |> Enum.reduce([], fn field, acc -> [input_key(field), field.name | acc] end)
      |> MapSet.new()

    params
    |> Map.keys()
    |> Enum.find(&(not MapSet.member?(allowed_keys, &1)))
  end

  @doc """
  Returns whether a field value should be omitted from JSON Schema validation data.

  Only omits `nil` for `optional: true`; keeps `nil` for `nullable: true` as validation input.

      iex> optional = %ExParamsSchema.Definition.Field{name: :label, type: :string, options: [optional: true]}
      iex> ExParamsSchema.Definition.Field.omit_from_validation?(optional, nil)
      true

      iex> nullable = %ExParamsSchema.Definition.Field{name: :label, type: :string, options: [nullable: true]}
      iex> ExParamsSchema.Definition.Field.omit_from_validation?(nullable, nil)
      false
  """
  @spec omit_from_validation?(t(), ExParamsSchema.value()) :: boolean()
  def omit_from_validation?(field, nil), do: optional?(field)
  def omit_from_validation?(_, _value), do: false
end
