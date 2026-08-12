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
  入力 map から値を取得するためのキーを返します。

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
  フィールド固有、継承、既定値の優先順でエラー理由を返します。

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
  フィールドが省略可能かを返します。

      iex> ExParamsSchema.Definition.Field.optional?(%ExParamsSchema.Definition.Field{name: :label, type: :string, options: [optional: true]})
      true
      iex> ExParamsSchema.Definition.Field.optional?(%ExParamsSchema.Definition.Field{name: :label, type: :string})
      false
  """
  @spec optional?(t()) :: boolean()
  def optional?(field), do: Keyword.get(field.options, :optional, false)

  @doc """
  入力 map からフィールドの値を取得します。

  `source:` で指定したキーを優先し、存在しない場合はフィールド名の atom key を参照します。

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
  入力に値がないフィールドの扱いを返します。

  `default:` があればその値を優先し、なければ `optional:` の設定に従います。

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
  省略可能なフィールドに対して、入力値を未指定相当として扱うかを返します。

  文字列では空文字に加えて空白だけの値も未指定相当です。

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
  フィールド定義に含まれない最初の入力キーを返します。

  各フィールドでは `source:` のキーとフィールド名の atom key の両方を許可します。

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
  JSON Schema 検証用データからフィールド値を省略するかを返します。

  `optional: true` の `nil` だけを省略し、`nullable: true` の `nil` は検証対象として残します。

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
