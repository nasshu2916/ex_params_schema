defmodule ExParamsSchema.Definition.Options do
  @moduledoc false

  @number_types [:float, :integer, :number]
  @membership_types [:any, :boolean, :float, :integer, :null, :number, :string]

  # option の追加時に、受け付けるキー・値・適用可能な型・JSON Schema への変換先をここだけで定義する。
  @rules [
    default: [field_only: true],
    enum: [validator: :non_empty_list, types: @membership_types, custom: false],
    error: [],
    in: [validator: :finite_membership, types: @membership_types, custom: false],
    json_schema: [validator: :json_schema],
    nullable: [validator: :boolean],
    optional: [field_only: true, validator: :boolean],
    source: [field_only: true, validator: :source],
    strict: [validator: :boolean, types: [:object]],
    minimum: [validator: :number, types: @number_types, json_schema_key: "minimum"],
    maximum: [validator: :number, types: @number_types, json_schema_key: "maximum"],
    min_length: [validator: :non_negative_integer, types: [:string], json_schema_key: "minLength"],
    max_length: [validator: :non_negative_integer, types: [:string], json_schema_key: "maxLength"],
    pattern: [validator: :binary, types: [:string], json_schema_key: "pattern"],
    format: [validator: :binary, types: [:string], json_schema_key: "format"],
    min_items: [validator: :non_negative_integer, types: [:array], json_schema_key: "minItems"],
    max_items: [validator: :non_negative_integer, types: [:array], json_schema_key: "maxItems"],
    unique_items: [validator: :boolean, types: [:array], json_schema_key: "uniqueItems"]
  ]

  @known_options Keyword.keys(@rules)
  @field_options for {name, rule} <- @rules, rule[:field_only], do: name
  @json_schema_options for {name, rule} <- @rules, key = rule[:json_schema_key], do: {name, key}

  @type rule :: keyword()

  @spec rules() :: Keyword.t(rule())
  def rules, do: @rules

  @spec rule(atom()) :: rule() | nil
  def rule(name), do: Keyword.get(@rules, name)

  @spec json_schema_options() :: Keyword.t(String.t())
  def json_schema_options, do: @json_schema_options

  @spec field_only() :: [atom()]
  def field_only, do: @field_options

  @spec known() :: [atom()]
  def known, do: @known_options

  @spec valid_value?(atom(), term()) :: boolean()
  def valid_value?(name, value) do
    case rule(name) do
      nil -> false
      rule -> predicate_valid?(rule[:validator], value)
    end
  end

  @spec allowed_for_type?(atom(), atom()) :: boolean()
  def allowed_for_type?(name, type) do
    case rule(name) do
      nil -> false
      rule when type == :custom -> Keyword.get(rule, :custom, true)
      rule -> is_nil(rule[:types]) or type in rule[:types]
    end
  end

  @spec validate!(Keyword.t()) :: :ok
  def validate!(options) do
    validate_keyword!(options)
    validate_known_options!(options)
  end

  @spec validate_custom!(Keyword.t()) :: :ok
  def validate_custom!(options) do
    validate_keyword!(options)
  end

  @spec validate_keyword!(list()) :: :ok
  defp validate_keyword!(options) do
    cond do
      not Keyword.keyword?(options) ->
        raise ArgumentError, "schema options must be a keyword list, got: #{inspect(options)}"

      Keyword.keys(options) |> Enum.uniq() |> length() != length(options) ->
        raise ArgumentError, "schema options must not contain duplicate keys: #{inspect(options)}"

      true ->
        :ok
    end
  end

  @spec validate_known_options!(Keyword.t()) :: :ok
  defp validate_known_options!(options) do
    case Keyword.keys(options) -- @known_options do
      [] -> :ok
      unknown -> raise ArgumentError, "unknown schema options: #{inspect(unknown)}"
    end
  end

  defp predicate_valid?(nil, _value), do: true
  defp predicate_valid?(:boolean, value), do: is_boolean(value)
  defp predicate_valid?(:number, value), do: is_number(value)
  defp predicate_valid?(:non_negative_integer, value), do: is_integer(value) and value >= 0
  defp predicate_valid?(:binary, value), do: is_binary(value)
  defp predicate_valid?(:source, value), do: is_atom(value) or is_binary(value)
  defp predicate_valid?(:non_empty_list, value), do: is_list(value) and value != []

  defp predicate_valid?(:finite_membership, value),
    do: is_list(value) or is_struct(value, Range) or is_struct(value, MapSet)

  defp predicate_valid?(:json_schema, value), do: is_map(value) or is_boolean(value)
end
