defmodule ExParamsSchema.TypeTest do
  use ExUnit.Case, async: true

  alias ExParamsSchema.Type
  alias ExParamsSchema.Type.{Adapter, DefinitionValidator, Typespec}

  defmodule InvalidOptionsType do
    def cast(value, _options), do: {:ok, value}
    def to_json(value, _options), do: value
    def json_schema(_options), do: %{"type" => "string"}
    def validate_options(_options), do: {:error, "options are invalid"}
  end

  defmodule InvalidOptionsResultType do
    def cast(value, _options), do: {:ok, value}
    def to_json(value, _options), do: value
    def json_schema(_options), do: %{"type" => "string"}
    def validate_options(_options), do: :invalid
  end

  defmodule InvalidOptionsDetailType do
    def cast(value, _options), do: {:ok, value}
    def to_json(value, _options), do: value
    def json_schema(_options), do: %{"type" => "string"}
    def validate_options(_options), do: {:error, :invalid_option}
  end

  defmodule InvalidSchemaType do
    def cast(value, _options), do: {:ok, value}
    def to_json(value, _options), do: value
    def json_schema(_options), do: :invalid
  end

  defmodule BooleanSchemaType do
    def cast(value, _options), do: {:ok, value}
    def to_json(value, _options), do: value
    def json_schema(_options), do: true
  end

  defmodule InvalidCastResultType do
    def cast(_value, _options), do: :invalid
    def to_json(value, _options), do: value
    def json_schema(_options), do: %{"type" => "string"}
  end

  defmodule InvalidValidateResultType do
    def cast(value, _options), do: {:ok, value}
    def to_json(value, _options), do: value
    def json_schema(_options), do: %{"type" => "string"}
    def validate(_value, _options), do: :invalid
  end

  defmodule IncompleteType do
    def cast(value, _options), do: {:ok, value}
  end

  defmodule RejectingType do
    def cast(_value, _options), do: {:error, :adapter_detail}
    def to_json(value, _options), do: value
    def json_schema(_options), do: %{"type" => "string"}
  end

  defmodule PassingType do
    def cast(value, _options), do: {:ok, value}
    def to_json(value, _options), do: value
    def json_schema(_options), do: %{"type" => "string"}
  end

  defmodule ValidatingType do
    def cast(value, options) when is_binary(value), do: {:ok, options[:prefix] <> value}
    def cast(_value, _options), do: {:error, :invalid_input}

    def to_json(value, options), do: options[:json_prefix] <> value
    def json_schema(options), do: %{"type" => options[:type]}

    def validate(value, options) do
      if String.ends_with?(value, options[:suffix]), do: :ok, else: {:error, :invalid_suffix}
    end
  end

  defmodule TypespecType do
    def typespec, do: quote(do: String.t())
  end

  defmodule StructWithoutType do
    defstruct [:value]
  end

  test "独自型の定義エラーを分かりやすく返す" do
    assert_raise ArgumentError, ~r/invalid schema at value: options are invalid/, fn ->
      Type.validate_definition!(InvalidOptionsType, [], ["value"])
    end

    assert_raise ArgumentError, ~r/invalid validate_options\/1 result: :invalid/, fn ->
      Type.validate_definition!(InvalidOptionsResultType, [], ["value"])
    end

    assert_raise ArgumentError, ~r/invalid validate_options\/1 result: \{:error, :invalid_option\}/, fn ->
      Type.validate_definition!(InvalidOptionsDetailType, [], ["value"])
    end

    assert_raise ArgumentError,
                 ~r/json_schema\/1 must return a map or boolean, got: :invalid/,
                 fn ->
                   Type.validate_definition!(InvalidSchemaType, [], ["value"])
                 end
  end

  test "独自型モジュールではない値と未コンパイルのモジュールを拒否する" do
    assert_raise ArgumentError, ~r/custom type module must be an atom, got: "invalid"/, fn ->
      Type.validate_definition!("invalid", [], ["value"])
    end

    assert_raise ArgumentError, ~r/could not compile custom type/, fn ->
      Type.validate_definition!(ExParamsSchema.TypeTest.UnknownType, [], ["value"])
    end

    assert_raise ArgumentError,
                 ~r/must implement \[to_json: 2, json_schema: 1\]/,
                 fn ->
                   Type.validate_definition!(IncompleteType, [], ["value"])
                 end
  end

  test "adapter固有の変換エラーをフィールドのreasonへ正規化する" do
    assert Type.cast(RejectingType, "value", [], :invalid_value) == {:error, :invalid_value}
  end

  test "未実装のoptional callbackには既定値を使う" do
    assert Type.validate_definition!(PassingType, [], ["value"]) == :ok
    assert Type.cast(PassingType, "value", [], :invalid_value) == {:ok, "value"}
  end

  test "booleanのJSON Schemaを返す独自型を受け入れる" do
    assert Type.validate_definition!(BooleanSchemaType, [], ["value"]) == :ok
    assert Type.json_schema(BooleanSchemaType, []) == true
  end

  test "optional validate callbackの成功・失敗とadapter callbackへの委譲を扱う" do
    options = [prefix: "id:", suffix: "ok", json_prefix: "json:", type: "string"]

    assert Type.cast(ValidatingType, "value-ok", options, :invalid_value) ==
             {:ok, "id:value-ok"}

    assert Type.cast(ValidatingType, "value", options, :invalid_value) == {:error, :invalid_value}
    assert Type.to_json(ValidatingType, "id:value-ok", options) == "json:id:value-ok"
    assert Type.json_schema(ValidatingType, options) == %{"type" => "string"}
  end

  test "独自型callbackの不正な戻り値を拒否する" do
    assert_raise ArgumentError, ~r/custom type cast\/2 must return/, fn ->
      Type.cast(InvalidCastResultType, "value", [], :invalid_value)
    end

    assert_raise ArgumentError,
                 ~r/InvalidValidateResultType\.validate\/2 returned invalid result: :invalid/,
                 fn ->
                   Type.cast(InvalidValidateResultType, "value", [], :invalid_value)
                 end
  end

  test "独自型のtypespec callbackとstructのt/0を解決する" do
    assert Type.typespec(TypespecType) |> Macro.to_string() == "String.t()"

    assert Type.typespec(ExParamsSchema.ValidationError) |> Macro.to_string() ==
             "ExParamsSchema.ValidationError.t()"

    assert Type.typespec(StructWithoutType) |> Macro.to_string() == "dynamic()"

    assert Type.typespec(ExParamsSchema.TypeTest.UnknownType) |> Macro.to_string() == "dynamic()"
  end

  test "内部コンポーネントへ公開APIの責務を委譲する" do
    assert Adapter.cast(PassingType, "value", [], :invalid_value) ==
             {:ok, "value"}

    assert DefinitionValidator.validate_definition!(PassingType, [], ["value"]) ==
             :ok

    assert Typespec.resolve(TypespecType) |> Macro.to_string() == "String.t()"
  end
end
