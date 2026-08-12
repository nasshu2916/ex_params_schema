defmodule ExParamsSchema do
  @moduledoc """
  A DSL for validating string-heavy params received by LiveViews, Phoenix controllers, JSON APIs,
  and similar sources, and casting them into typed structs.

  In a module that uses `ExParamsSchema`, declaring `field/2` or `field/3` inside a `defschema/1`
  or `defschema/2` block generates a struct, `t/0`, and `parse/1`.

      defmodule ExampleParams do
        use ExParamsSchema

        defschema do
          field :id, :integer, minimum: 1, maximum: 24
          field :value, :integer, minimum: 0, maximum: 255
        end
      end

      ExampleParams.parse(%{"id" => "1", "value" => "128"})
      #=> {:ok, %ExampleParams{id: 1, value: 128}}

  Combine `:boolean`, `:date`, `:datetime`, `:integer`, `:float`, `:number`, `:string`, `:null`,
  `:any`, atom enums, maps, and lists. Strings are cast before standard constraints are validated
  with JSON Schema Draft 7. See the README and `docs/` for details.
  """

  alias ExParamsSchema.{Compiler, Definition, Schema}
  alias ExParamsSchema.Schema.Options

  @typedoc "A field value resolved at runtime."
  @type value :: dynamic()

  @typedoc "An error reason that callers can choose freely."
  @type error_reason :: dynamic()

  @typedoc "A field-level validation error returned by `parse_detailed/1` and `parse_detailed/2`."
  @type validation_error :: ExParamsSchema.ValidationError.t()

  @typedoc "A reusable compiled schema returned by `compile!/1`."
  @opaque compiled_schema :: %{required(:__struct__) => module(), optional(atom()) => term()}

  @type scalar_field_type ::
          :any
          | :boolean
          | :date
          | :datetime
          | :float
          | :integer
          | :null
          | :number
          | :string

  @type atom_enum_type :: {kind :: :enum, allowed_values :: [atom()]}
  @type custom_field_type :: {kind :: :custom, module :: module(), options :: keyword()}
  @type object_field_type :: %{optional(field_name()) => definition()}
  @type array_field_type :: [definition()]

  @type field_type ::
          scalar_field_type()
          | atom_enum_type()
          | custom_field_type()
          | object_field_type()
          | array_field_type()

  @type definition_with_options :: {field_type :: field_type(), options :: field_options()}
  @type custom_definition :: {module :: module(), options :: keyword()}
  @type definition :: field_type() | definition_with_options() | custom_definition()

  @type field_options :: [
          source: String.t() | atom(),
          in: [value()] | Range.t() | MapSet.t(),
          enum: [value()],
          minimum: number(),
          maximum: number(),
          min_length: non_neg_integer(),
          max_length: non_neg_integer(),
          pattern: String.t(),
          format: String.t(),
          min_items: non_neg_integer(),
          max_items: non_neg_integer(),
          unique_items: boolean(),
          json_schema: map() | boolean(),
          nullable: boolean(),
          optional: boolean(),
          strict: boolean(),
          default: value(),
          error: error_reason()
        ]

  @type field_name :: atom()
  @type field :: {name :: field_name(), type :: field_type(), options :: field_options()}
  @type schema_definition :: %{required(field_name()) => definition()}
  @type schema_options :: keyword()
  @type parsed_params :: map()
  @type parse_result :: {:ok, params :: parsed_params()} | {:error, reason :: error_reason()}
  @type detailed_parse_result ::
          {:ok, params :: parsed_params()} | {:error, errors :: [validation_error()]}

  @doc """
  Enables the schema DSL in a params module.

  Imports `defschema/1`, `defschema/2`, `field/2`, and `field/3`. At compile time, it validates
  declarations and generates a struct, `t/0`, and `parse/1`.
  """
  defmacro __using__(options) do
    schema_options = Options.normalize!(options, "use ExParamsSchema")

    quote do
      import ExParamsSchema, only: [defschema: 1, defschema: 2, field: 2, field: 3]

      Module.register_attribute(__MODULE__, :event_param_fields, accumulate: true)
      @event_param_strict unquote(schema_options.strict)
      @before_compile ExParamsSchema
    end
  end

  @doc """
  Declares a field with optional settings.

      field :id, :integer,
        source: "input-id",
        minimum: 1,
        error: :invalid_id

  `source:` specifies the input key. Fields also support `optional:`, `nullable:`, `default:`, and
  `error:`. See the README for type-specific constraints.

  ## Compile-time errors

  Unsupported types, unknown or duplicate options, invalid option values, constraints that do not
  apply to the type, duplicate field names or input keys, and defaults that violate constraints
  raise `ArgumentError`.
  """
  defmacro field(name, type, options \\ []) do
    quote bind_quoted: [name: name, type: type, options: options] do
      @event_param_fields {name, type, options}
    end
  end

  @doc """
  Declares a schema.

      defschema do
        field :page, :integer, default: 1, minimum: 1
        field :query, :string, optional: true
      end

  Declare fields with `field/2` or `field/3` inside the block. Field names and input keys must be
  unique. The schema inherits strict mode from `use ExParamsSchema, strict: true` when configured.

  `strict:` overrides the `use ExParamsSchema` setting for this schema.

      defschema strict: true do
        field :identifier, :integer
      end

  With `strict: true`, unknown input keys are rejected.

  ## Compile-time errors

  Options other than `strict:`, as well as invalid field types, options, constraints, or defaults,
  raise `ArgumentError`.
  """
  defmacro defschema(options \\ [], do: block) do
    quote do
      ExParamsSchema.configure_defschema!(__MODULE__, unquote(options))
      unquote(block)
    end
  end

  @doc false
  @spec configure_defschema!(module(), keyword()) :: :ok
  def configure_defschema!(module, options) do
    default_options = %Options{
      strict: Module.get_attribute(module, :event_param_strict, false)
    }

    schema_options = Options.normalize!(options, "defschema", default_options)

    Module.put_attribute(module, :event_param_strict, schema_options.strict)
  end

  @doc """
  Compiles a map-based schema definition into a runtime schema.

      iex> schema = ExParamsSchema.compile!(%{
      ...>   id: {:integer, source: "input-id", minimum: 1},
      ...>   enabled: {:boolean, default: false}
      ...> })
      iex> ExParamsSchema.parse(%{"input-id" => "1", "enabled" => "true"}, schema)
      {:ok, %{enabled: true, id: 1}}

  Pass the resulting schema to `parse/2`. This is useful with `ExParamsSchema.Handler` or whenever
  you want to parse maps without generating a struct.

  ## Raises

  Raises `ArgumentError` for an invalid definition. Keys must be atoms.
  """
  @spec compile!(schema_definition(), schema_options()) :: compiled_schema()
  def compile!(definition, options \\ []) when is_map(definition) and is_list(options) do
    {fields, schema_options} = compile_schema_definition!(definition, options, "compile!")

    Schema.compile!(fields, schema_options.strict)
  end

  @doc """
  Returns JSON Schema Draft 7 from a compiled schema or a map-based field definition.

      iex> ExParamsSchema.json_schema(%{count: {:integer, minimum: 1}})
      ...> |> get_in(["properties", "count"])
      %{"minimum" => 1, "type" => "integer"}

  A map-based definition does not need to be passed to `compile!/1` first. To set `strict: true`, use
  `json_schema(definition, strict: true)`. Modules using `defschema` can call the generated
  `json_schema/0` with no arguments.
  """
  @spec json_schema(compiled_schema()) :: map()
  @spec json_schema(schema_definition()) :: map()
  @spec json_schema(schema_definition(), schema_options()) :: map()
  def json_schema(schema_or_definition, options \\ [])

  def json_schema(%Schema{} = schema, _) do
    Schema.json_schema(schema)
  end

  def json_schema(definition, options)
      when is_map(definition) and not is_struct(definition) and is_list(options) do
    {fields, schema_options} = compile_schema_definition!(definition, options, "json_schema")

    Schema.json_schema(fields, schema_options.strict)
  end

  @doc """
  Validates and casts parameters with a compiled schema.

      iex> schema = ExParamsSchema.compile!(%{count: {:integer, minimum: 1}})
      iex> ExParamsSchema.parse(%{"count" => "2"}, schema)
      {:ok, %{count: 2}}

  Returns the cast map on success. On failure, returns the field's `error:` value or
  `{:invalid_param, field_name}` when omitted. Non-map input returns `{:error, :invalid_params}`.
  """
  @spec parse(map(), compiled_schema()) :: parse_result()
  defdelegate parse(params, schema), to: ExParamsSchema.Parser

  @doc """
  Validates and casts parameters with a compiled schema, returning every validation error on failure.

      iex> schema = ExParamsSchema.compile!(%{count: {:integer, minimum: 1}})
      iex> match?(
      ...>   {:error, [%ExParamsSchema.ValidationError{path: ["count"], keyword: :minimum}]},
      ...>   ExParamsSchema.parse_detailed(%{"count" => "0"}, schema)
      ...> )
      true

  Each error's `path`, `keyword`, and `reason` can be used for UI field messages. `reason` is the
  same `error:` value returned by `parse/2`. Errors are collected from every field and nested object
  or array item, including casting, missing required values, and unknown strict-mode keys. Cast
  errors use `:cast` as their `keyword`; unknown keys use `:additional_properties`.
  """
  @spec parse_detailed(map(), compiled_schema()) :: detailed_parse_result()
  defdelegate parse_detailed(params, schema), to: ExParamsSchema.Parser

  defmacro __before_compile__(environment) do
    Compiler.before_compile(environment)
  end

  @type compiled_schema_definition :: {fields :: [Definition.Field.t()], options :: Options.t()}

  @spec compile_schema_definition!(schema_definition(), schema_options(), String.t()) ::
          compiled_schema_definition()
  defp compile_schema_definition!(definition, options, function_name) do
    fields = Definition.compile!(definition)
    schema_options = Options.normalize!(options, function_name)

    {fields, schema_options}
  end
end
