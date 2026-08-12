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
      受信したパラメーターを検証し、このモジュールの構造体へ変換します。

      成功時は `{:ok, t()}`、失敗時は `{:error, reason}` を返します。map 以外の入力には
      `{:error, :invalid_params}` を返します。
      """
      @spec parse(term()) :: {:ok, t()} | {:error, ExParamsSchema.error_reason()}
      def parse(params) do
        ExParamsSchema.Parser.parse(params, __MODULE__, unquote(schema_ast))
      end

      @doc """
      受信したパラメーターを検証・変換し、失敗時にフィールド単位の詳細エラーを返します。

      通常の `parse/1` と同じエラー理由を保ったまま、UI 表示向けの `path` と `keyword` を取得できます。
      """
      @spec parse_detailed(term()) :: {:ok, t()} | {:error, [ExParamsSchema.validation_error()]}
      def parse_detailed(params) do
        ExParamsSchema.Parser.parse_detailed(params, __MODULE__, unquote(schema_ast))
      end

      @doc """
      このモジュールの定義から生成した JSON Schema Draft 7 を返します。
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
