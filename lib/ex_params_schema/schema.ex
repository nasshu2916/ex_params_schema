defmodule ExParamsSchema.Schema do
  @moduledoc """
  Represents a compiled schema containing normalized fields, JSON Schema, and validation data.

  It is created by `ExParamsSchema.compile!/2`. The struct's internal representation and its
  direct-operation functions may change, so use the public `ExParamsSchema` API in normal use.
  """

  alias ExParamsSchema.Definition.Field
  alias ExParamsSchema.Schema.{Defaults, ErrorPath, JsonPointer, JsonSchema, Projector}

  defstruct [
    :fields,
    :json_schema,
    :resolved,
    :strict,
    errors: []
  ]

  @type t :: %__MODULE__{
          fields: [Field.t()],
          strict: boolean(),
          json_schema: map(),
          resolved: ExJsonSchema.Schema.Root.t(),
          errors: [error_definition()]
        }

  @type error_definition :: {
          pattern :: JsonPointer.pattern(),
          error_reason :: ExParamsSchema.error_reason(),
          order :: non_neg_integer()
        }
  @type error_reference :: {order :: non_neg_integer(), error_reason :: ExParamsSchema.error_reason()}
  @type resolved_error_path :: {
          order :: non_neg_integer(),
          error_reason :: ExParamsSchema.error_reason(),
          path :: JsonPointer.resolved_path()
        }

  @doc """
  Compiles validated fields into a schema that can be reused at runtime.

  `ExParamsSchema.Definition` validates and compiles field definitions. Normally, use
  `ExParamsSchema.compile!/2`, which accepts a map-based definition. Field definitions are also
  accepted for backward compatibility and delegated to `Definition.compile_fields!/1`.

      iex> fields = ExParamsSchema.Definition.compile_fields!([{:count, :integer, [minimum: 1]}])
      iex> schema = ExParamsSchema.Schema.compile!(fields)
      iex> schema.strict
      false
      iex> get_in(schema.json_schema, ["properties", "count"])
      %{"minimum" => 1, "type" => "integer"}
  """
  @spec compile!([ExParamsSchema.field()] | [Field.t()], boolean()) :: t()
  def compile!(fields, strict \\ false) when is_list(fields) and is_boolean(strict) do
    fields = compile_fields!(fields)
    {json_schema, errors} = JsonSchema.build(fields, strict)
    resolved = ExJsonSchema.Schema.resolve(json_schema)
    fields = Defaults.normalize!(fields, resolved)

    %__MODULE__{
      fields: fields,
      json_schema: json_schema,
      resolved: resolved,
      strict: strict,
      errors: errors
    }
  end

  @doc """
  Returns JSON Schema Draft 7 from a compiled schema or validated fields. Field definitions are
  delegated to `Definition.compile_fields!/1` for backward compatibility.

  When `strict` is specified for a compiled schema, regenerates JSON Schema with that setting.
  Otherwise, returns the JSON Schema generated at compile time.

      iex> fields = ExParamsSchema.Definition.compile_fields!([{:name, :string, []}])
      iex> ExParamsSchema.Schema.json_schema(fields)["required"]
      ["name"]
  """
  @spec json_schema(t()) :: map()
  @spec json_schema(t(), boolean() | nil) :: map()
  @spec json_schema([ExParamsSchema.field()] | [Field.t()]) :: map()
  @spec json_schema([ExParamsSchema.field()] | [Field.t()], boolean() | nil) :: map()
  def json_schema(fields, strict \\ nil)
  def json_schema(%__MODULE__{json_schema: json_schema}, nil), do: json_schema
  def json_schema(%__MODULE__{strict: strict, json_schema: json_schema}, strict), do: json_schema

  def json_schema(%__MODULE__{} = schema, strict) when is_boolean(strict) do
    {json_schema, _errors} = JsonSchema.build(schema.fields, strict)
    json_schema
  end

  def json_schema(fields, nil) when is_list(fields), do: json_schema(fields, false)

  def json_schema(fields, strict) when is_list(fields) and is_boolean(strict) do
    fields = compile_fields!(fields)
    {json_schema, _errors} = JsonSchema.build(fields, strict)
    json_schema
  end

  @doc """
  Converts cast values into values that JSON Schema can validate.

      iex> fields = ExParamsSchema.Definition.compile_fields!([{:published_on, :date, []}])
      iex> schema = ExParamsSchema.Schema.compile!(fields)
      iex> ExParamsSchema.Schema.validation_data(schema, %{published_on: ~D[2026-07-23]})
      %{"published_on" => "2026-07-23"}
  """
  @spec validation_data(t(), map()) :: map()
  def validation_data(%__MODULE__{} = schema, parsed),
    do: Projector.project(schema.fields, parsed)

  @doc "Returns the declaration order and error reason for a JSON Pointer."
  @deprecated "Use resolve_error_path/2, which also returns the resolved path"
  @spec error_for_path(t(), String.t()) :: error_reference() | nil
  def error_for_path(%__MODULE__{} = schema, path) do
    case resolve_error_path(schema, path) do
      {order, reason, _resolved_path} -> {order, reason}
      nil -> nil
    end
  end

  @doc "Returns the declaration order, error reason, and resolved path for a JSON Pointer."
  @spec resolve_error_path(t(), String.t()) :: resolved_error_path() | nil
  def resolve_error_path(%__MODULE__{} = schema, pointer), do: ErrorPath.resolve(schema.errors, pointer)

  @spec compile_fields!([ExParamsSchema.field()] | [Field.t()]) :: [Field.t()]
  defp compile_fields!(fields) do
    case Enum.split_with(fields, &match?(%Field{}, &1)) do
      {[], definitions} ->
        ExParamsSchema.Definition.compile_fields!(definitions)

      {compiled_fields, []} ->
        compiled_fields

      {_compiled_fields, _definitions} ->
        raise ArgumentError,
              "schema fields must be either field definitions or compiled ExParamsSchema.Definition.Field structs; mixed lists are not supported"
    end
  end
end
