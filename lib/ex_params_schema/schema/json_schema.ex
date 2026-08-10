defmodule ExParamsSchema.Schema.JsonSchema do
  @moduledoc """
  正規化済みフィールドから JSON Schema Draft 7 を組み立てます。

  `ExParamsSchema.json_schema/1`・`json_schema/2` を支える内部モジュールです。
  """

  alias ExParamsSchema.Definition
  alias ExParamsSchema.Definition.Field

  @draft7 "http://json-schema.org/draft-07/schema#"

  @type schema_document :: map()
  @type build_result :: {
          schema :: schema_document(),
          error_definitions :: [ExParamsSchema.Schema.error_definition()]
        }

  @doc """
  コンパイル済みフィールドから JSON Schema とエラーパス定義を組み立てます。

      iex> fields = ExParamsSchema.Definition.compile_fields!([{:count, :integer, [minimum: 1]}])
      iex> {schema, errors} = ExParamsSchema.Schema.JsonSchema.build(fields, false)
      iex> get_in(schema, ["properties", "count"])
      %{"minimum" => 1, "type" => "integer"}
      iex> errors
      [{["count"], {:invalid_param, :count}, 0}]
  """
  @spec build([Field.t()], boolean()) :: build_result()
  def build(fields, strict) do
    {properties, required, errors, _next_order} = build_fields(fields, [], nil, 0)

    schema =
      %{
        "$schema" => @draft7,
        "type" => "object",
        "properties" => properties,
        "required" => required
      }
      |> maybe_put_strict(strict)

    {schema, errors}
  end

  @spec build_fields(
          [Field.t()],
          ExParamsSchema.Schema.JsonPointer.pattern(),
          ExParamsSchema.error_reason() | nil,
          non_neg_integer()
        ) :: {map(), [String.t()], [ExParamsSchema.Schema.error_definition()], non_neg_integer()}
  defp build_fields(fields, parent_path, inherited_reason, initial_order) do
    Enum.reduce(fields, {%{}, [], [], initial_order}, fn %Field{} = field, {properties, required, errors, order} ->
      name_string = Atom.to_string(field.name)
      path = parent_path ++ [name_string]
      reason = Field.error_reason(field, inherited_reason)

      {property, nested_errors, next_order} =
        build_type(field.type, field.options, path, reason, order + 1)

      required = if Field.optional?(field), do: required, else: [name_string | required]

      {
        Map.put(properties, name_string, property),
        required,
        errors ++ [{path, reason, order} | nested_errors],
        next_order
      }
    end)
    |> then(fn {properties, required, errors, order} ->
      {properties, Enum.reverse(required), errors, order}
    end)
  end

  @spec build_type(
          Field.normalized_type(),
          ExParamsSchema.field_options(),
          ExParamsSchema.Schema.JsonPointer.pattern(),
          ExParamsSchema.error_reason() | nil,
          non_neg_integer()
        ) :: {map() | boolean(), [ExParamsSchema.Schema.error_definition()], non_neg_integer()}
  defp build_type({:enum, allowed}, options, _path, _reason, order) do
    allowed = Enum.map(allowed, &Atom.to_string/1)
    schema = %{"type" => "string", "enum" => nullable_values(allowed, options)}
    {nullable_schema(schema, options), [], order}
  end

  defp build_type({:custom, module, custom_options}, options, _path, _reason, order) do
    schema = ExParamsSchema.Type.json_schema(module, custom_options)

    schema =
      schema
      |> custom_schema_with_constraints(options)
      |> nullable_schema(options)

    {schema, [], order}
  end

  defp build_type({:array, item_type, item_options}, options, path, reason, order) do
    item_reason = Keyword.get(item_options, :error, reason)

    {item, nested_errors, next_order} =
      build_type(item_type, item_options, path ++ [:index], item_reason, order + 1)

    schema =
      %{"type" => "array", "items" => item}
      |> put_constraints(options)
      |> nullable_schema(options)

    {schema, [{path ++ [:index], item_reason, order} | nested_errors], next_order}
  end

  defp build_type({:object, fields}, options, path, reason, order) do
    {properties, required, nested_errors, next_order} =
      build_fields(fields, path, reason, order + 1)

    schema =
      %{"type" => "object", "properties" => properties, "required" => required}
      |> put_constraints(options)
      |> maybe_put_strict(Keyword.get(options, :strict, false))
      |> nullable_schema(options)

    {schema, nested_errors, next_order}
  end

  defp build_type(:date, options, _path, _reason, order) do
    schema =
      %{"type" => "string", "format" => "date"}
      |> put_constraints(options)
      |> nullable_schema(options)

    {schema, [], order}
  end

  defp build_type(:datetime, options, _path, _reason, order) do
    schema =
      %{"type" => "string", "format" => "date-time"}
      |> put_constraints(options)
      |> nullable_schema(options)

    {schema, [], order}
  end

  defp build_type(type, options, _path, _reason, order) do
    schema =
      type |> json_type() |> put_type() |> put_constraints(options) |> nullable_schema(options)

    {schema, [], order}
  end

  @spec json_type(ExParamsSchema.scalar_field_type()) :: String.t() | nil
  defp json_type(:any), do: nil
  defp json_type(:boolean), do: "boolean"
  defp json_type(:float), do: "number"
  defp json_type(:integer), do: "integer"
  defp json_type(:null), do: "null"
  defp json_type(:number), do: "number"
  defp json_type(:string), do: "string"

  @spec put_type(String.t() | nil) :: map()
  defp put_type(nil), do: %{}
  defp put_type(type), do: %{"type" => type}

  @spec put_constraints(map(), ExParamsSchema.field_options()) :: map() | boolean()
  defp put_constraints(schema, options) do
    schema
    |> put_standard_constraints(options)
    |> put_membership(options)
    |> put_json_schema(options)
  end

  @spec put_standard_constraints(map(), ExParamsSchema.field_options()) :: map()
  defp put_standard_constraints(schema, options) do
    Enum.reduce(Definition.json_schema_options(), schema, fn {option, json_key}, schema ->
      put_option(schema, options, option, json_key)
    end)
  end

  @spec put_json_schema(map(), ExParamsSchema.field_options()) :: map() | boolean()
  defp put_json_schema(schema, options) do
    case Keyword.fetch(options, :json_schema) do
      {:ok, true} -> schema
      {:ok, false} -> false
      {:ok, fragment} -> deep_merge_schema(schema, stringify_schema_keys(fragment))
      :error -> schema
    end
  end

  @spec deep_merge_schema(map(), map()) :: map()
  defp deep_merge_schema(schema, fragment) do
    Map.merge(schema, fragment, fn _key, dsl_value, fragment_value ->
      deep_merge_schema_value(dsl_value, fragment_value)
    end)
  end

  @spec deep_merge_schema_value(term(), term()) :: term()
  defp deep_merge_schema_value(dsl_value, fragment_value)
       when is_map(dsl_value) and is_map(fragment_value),
       do: deep_merge_schema(dsl_value, fragment_value)

  defp deep_merge_schema_value(_dsl_value, fragment_value), do: fragment_value

  @spec maybe_put_strict(map(), boolean()) :: map()
  defp maybe_put_strict(schema, true), do: Map.put(schema, "additionalProperties", false)
  defp maybe_put_strict(schema, false), do: schema

  @spec stringify_schema_keys(term()) :: term()
  defp stringify_schema_keys(schema) when is_map(schema) do
    Map.new(schema, fn {key, value} -> {to_string(key), stringify_schema_keys(value)} end)
  end

  defp stringify_schema_keys(schema) when is_list(schema),
    do: Enum.map(schema, &stringify_schema_keys/1)

  defp stringify_schema_keys(value), do: value

  @spec put_option(map(), ExParamsSchema.field_options(), atom(), String.t()) :: map()
  defp put_option(schema, options, option, json_key) do
    case Keyword.fetch(options, option) do
      {:ok, value} -> Map.put(schema, json_key, value)
      :error -> schema
    end
  end

  @spec put_membership(map(), ExParamsSchema.field_options()) :: map()
  defp put_membership(schema, options) do
    case Keyword.fetch(options, :enum) do
      {:ok, values} -> Map.put(schema, "enum", nullable_values(values, options))
      :error -> put_in_membership(schema, options)
    end
  end

  @spec put_in_membership(map(), ExParamsSchema.field_options()) :: map()
  defp put_in_membership(schema, options) do
    case Keyword.fetch(options, :in) do
      {:ok, values} -> Map.put(schema, "enum", nullable_values(Enum.to_list(values), options))
      :error -> schema
    end
  end

  @spec nullable_schema(map() | boolean(), ExParamsSchema.field_options()) :: map() | boolean()
  defp nullable_schema(schema, _options) when is_boolean(schema), do: schema

  defp nullable_schema(schema, options) do
    if Keyword.get(options, :nullable, false) do
      case Map.fetch(schema, "type") do
        {:ok, "null"} -> schema
        {:ok, types} when is_list(types) -> Map.put(schema, "type", Enum.uniq(types ++ ["null"]))
        {:ok, type} -> Map.put(schema, "type", [type, "null"])
        :error -> schema
      end
    else
      schema
    end
  end

  @spec nullable_values([term()], ExParamsSchema.field_options()) :: [term()]
  defp nullable_values(values, options) do
    if Keyword.get(options, :nullable, false), do: Enum.uniq([nil | values]), else: values
  end

  @spec custom_schema_with_constraints(map() | boolean(), ExParamsSchema.field_options()) :: map() | boolean()
  defp custom_schema_with_constraints(schema, options) when is_map(schema),
    do: put_constraints(schema, options)

  # boolean schema は map とマージできないため、true は空の schema と同じように扱う。
  # false は常に不許可を表すため、field option で許可へ上書きしない。
  defp custom_schema_with_constraints(true, options), do: put_constraints(%{}, options)
  defp custom_schema_with_constraints(false, _options), do: false
end
