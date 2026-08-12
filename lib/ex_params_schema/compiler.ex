defmodule ExParamsSchema.Compiler do
  @moduledoc """
  Generates structs and related functions at compile time from fields declared with
  `use ExParamsSchema`.

  This internal module supports macro expansion and is not normally called directly.
  """

  alias ExParamsSchema.Definition.{Field, Typespec}

  @spec before_compile(Macro.Env.t()) :: Macro.t()
  def before_compile(environment) do
    schema = compile_schema(environment.module)
    schema_ast = Macro.escape(schema)
    struct_fields = Enum.map(schema.fields, &struct_field/1)
    struct_type = Typespec.struct_type(schema.fields)

    quote do
      defstruct unquote(Macro.escape(struct_fields))

      @type t :: unquote(struct_type)

      @doc """
      Validates received parameters and casts them into this module's struct.

      Returns `{:ok, t()}` on success and `{:error, reason}` on failure. Non-map input returns
      `{:error, :invalid_params}`.
      """
      @spec parse(term()) :: {:ok, t()} | {:error, ExParamsSchema.error_reason()}
      def parse(params) do
        ExParamsSchema.Parser.parse(params, __MODULE__, unquote(schema_ast))
      end

      @doc """
      Validates and casts received parameters, returning detailed, field-level errors on failure.

      Preserves the error reasons from `parse/1` while providing `path` and `keyword` for UI display.
      """
      @spec parse_detailed(term()) :: {:ok, t()} | {:error, [ExParamsSchema.validation_error()]}
      def parse_detailed(params) do
        ExParamsSchema.Parser.parse_detailed(params, __MODULE__, unquote(schema_ast))
      end

      @doc """
      Returns JSON Schema Draft 7 generated from this module's definition.
      """
      @spec json_schema() :: map()
      def json_schema do
        ExParamsSchema.json_schema(unquote(schema_ast))
      end
    end
  end

  @spec compile_schema(module()) :: ExParamsSchema.Schema.t()
  defp compile_schema(module) do
    fields =
      module
      |> Module.get_attribute(:event_param_fields)
      |> Enum.reverse()
      |> ExParamsSchema.Definition.compile_fields!()

    strict = Module.get_attribute(module, :event_param_strict) || false
    ExParamsSchema.Schema.compile!(fields, strict)
  end

  @spec struct_field(Field.t()) :: {atom(), ExParamsSchema.value()}
  defp struct_field(%Field{} = field) do
    {field.name, Keyword.get(field.options, :default)}
  end
end
