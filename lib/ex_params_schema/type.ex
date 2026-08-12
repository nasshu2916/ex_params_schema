defmodule ExParamsSchema.Type do
  @moduledoc """
  Specifies how to use custom types as `ExParamsSchema` fields.

  An adapter casts external input to a domain or primitive value, then converts that value to a
  JSON-compatible value for JSON Schema validation. `ex_json_schema`, rather than the adapter,
  validates standard constraints.

  Implement `typespec/0` to specify the generated params struct's field type as an AST. When it
  is not implemented, a struct adapter's `t/0` is used; all other adapters use `dynamic()`.

  A minimal adapter implements the three required callbacks.

      defmodule MyApp.TrimmedString do
        @behaviour ExParamsSchema.Type

        @impl true
        def cast(value, _options) when is_binary(value), do: {:ok, String.trim(value)}
        def cast(_value, _options), do: {:error, :not_a_string}

        @impl true
        def to_json(value, _options), do: value

        @impl true
        def json_schema(_options), do: %{"type" => "string"}

        @impl true
        def typespec, do: quote(do: String.t())
      end

  Specify `{Module, adapter_options}` as the field type. Specify field options outside the tuple.

      field :slug, {MyApp.TrimmedString, []}, min_length: 1, error: :invalid_slug
  """

  @type json_array :: [json_value()]
  @type json_object :: %{String.t() => json_value()}
  @type json_value :: boolean() | number() | String.t() | nil | json_array() | json_object()
  @type cast_result :: {:ok, value :: term()} | {:error, detail :: term()}

  @doc "外部入力を adapter の値へ変換します。変換不能な場合は `{:error, detail}` を返します。"
  @callback cast(input :: term(), options :: keyword()) :: cast_result()

  @doc "adapter の値を JSON Schema 検証用の JSON 互換値へ変換します。"
  @callback to_json(value :: term(), options :: keyword()) :: json_value()

  @doc "adapter の値に対応する追加の JSON Schema を返します。"
  @callback json_schema(options :: keyword()) :: map() | boolean()

  @doc "変換済みの adapter 値に固有の制約を適用します。"
  @callback validate(value :: term(), options :: keyword()) :: :ok | {:error, detail :: term()}

  @doc "フィールド宣言に渡された adapter 固有の option を検証します。"
  @callback validate_options(options :: keyword()) :: :ok | {:error, String.t()}

  @doc "生成される params 構造体のフィールド型を表す AST を返します。"
  @callback typespec() :: Macro.t()

  @optional_callbacks validate: 2, validate_options: 1, typespec: 0

  # 公開モジュールは adapter 実装者向けの仕様に限定し、実行詳細は内部モジュールへ分離する。
  @doc false
  @spec validate_definition!(module(), keyword(), [String.t()]) :: :ok
  defdelegate validate_definition!(module, options, path), to: ExParamsSchema.Type.DefinitionValidator

  @doc false
  @spec cast(module(), term(), keyword(), term()) :: cast_result()
  defdelegate cast(module, value, options, reason), to: ExParamsSchema.Type.Adapter

  @doc false
  @spec json_schema(module(), keyword()) :: map() | boolean()
  defdelegate json_schema(module, options), to: ExParamsSchema.Type.Adapter

  @doc false
  @spec to_json(module(), term(), keyword()) :: json_value()
  defdelegate to_json(module, value, options), to: ExParamsSchema.Type.Adapter

  @doc false
  @spec typespec(module()) :: Macro.t()
  defdelegate typespec(module), to: ExParamsSchema.Type.Typespec
end
