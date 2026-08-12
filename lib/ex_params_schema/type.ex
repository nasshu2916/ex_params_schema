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

  @doc "Casts external input to an adapter value, returning `{:error, detail}` when casting fails."
  @callback cast(input :: term(), options :: keyword()) :: cast_result()

  @doc "Converts an adapter value into a JSON-compatible value for JSON Schema validation."
  @callback to_json(value :: term(), options :: keyword()) :: json_value()

  @doc "Returns additional JSON Schema for an adapter value."
  @callback json_schema(options :: keyword()) :: map() | boolean()

  @doc "Applies constraints specific to a cast adapter value."
  @callback validate(value :: term(), options :: keyword()) :: :ok | {:error, detail :: term()}

  @doc "Validates adapter-specific options provided in a field declaration."
  @callback validate_options(options :: keyword()) :: :ok | {:error, String.t()}

  @doc "Returns the AST representing the field type in the generated params struct."
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
