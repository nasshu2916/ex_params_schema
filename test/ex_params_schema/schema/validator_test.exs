defmodule ExParamsSchema.Schema.ValidatorTest do
  use ExUnit.Case, async: true

  alias ExParamsSchema.Schema
  alias ExParamsSchema.Schema.Validator
  alias ExParamsSchema.ValidationError

  describe "validate/2" do
    test "JSON Schemaを満たすデータは成功する" do
      schema = schema([{:count, :integer, [minimum: 1]}])

      assert Validator.validate(schema, %{"count" => 1}) == :ok
    end

    test "対応するerrorを最も早い宣言順で返す" do
      schema =
        schema([
          {:first, :integer, [minimum: 1, error: :invalid_first]},
          {:second, :integer, [minimum: 1, error: :invalid_second]}
        ])

      assert Validator.validate(schema, %{"first" => 0, "second" => 0}) ==
               {:error, :invalid_first}
    end

    test "ネストしたobject・array itemには最も具体的なerrorを対応付ける" do
      schema =
        schema([
          {:payload,
           %{
             entries: {[{:integer, minimum: 1, error: :invalid_entry}], error: :invalid_entries}
           }, [error: :invalid_payload]}
        ])

      assert Validator.validate(schema, %{"payload" => %{"entries" => [0]}}) ==
               {:error, :invalid_entry}
    end

    test "対応するerror定義がない場合は汎用エラーへ正規化する" do
      schema = schema([{:count, :integer, [minimum: 1, error: :invalid_count]}])

      assert Validator.validate(%{schema | errors: []}, %{"count" => 0}) ==
               {:error, :invalid_params}
    end
  end

  describe "validate_detailed/2" do
    test "JSON Schemaを満たすデータは成功する" do
      schema = schema([{:count, :integer, [minimum: 1]}])

      assert Validator.validate_detailed(schema, %{"count" => 1}) == :ok
    end

    test "通常のJSON Schemaエラーをpath、keyword、reason、detailsへ変換する" do
      schema = schema([{:count, :integer, [minimum: 2, error: :invalid_count]}])

      assert Validator.validate_detailed(schema, %{"count" => 1}) ==
               {:error,
                [
                  %ValidationError{
                    path: ["count"],
                    keyword: :minimum,
                    reason: :invalid_count,
                    details: %{expected: 2, exclusive?: false}
                  }
                ]}
    end

    test "requiredエラーを欠落フィールドごとに展開し、宣言順に並べる" do
      schema =
        schema([
          {:first, :integer, [error: :invalid_first]},
          {:second, :string, [error: :invalid_second]}
        ])

      assert Validator.validate_detailed(schema, %{}) ==
               {:error,
                [
                  %ValidationError{
                    path: ["first"],
                    keyword: :required,
                    reason: :invalid_first,
                    details: %{}
                  },
                  %ValidationError{
                    path: ["second"],
                    keyword: :required,
                    reason: :invalid_second,
                    details: %{}
                  }
                ]}
    end

    test "対応するerror定義がない詳細エラーはJSON Pointerのpathと汎用reasonを返す" do
      schema = schema([{:entries, [{:integer, minimum: 1, error: :invalid_entry}], []}])

      assert Validator.validate_detailed(%{schema | errors: []}, %{"entries" => [1, 0]}) ==
               {:error,
                [
                  %ValidationError{
                    path: ["entries", 1],
                    keyword: :minimum,
                    reason: :invalid_params,
                    details: %{expected: 1, exclusive?: false}
                  }
                ]}
    end
  end

  defp schema(fields), do: Schema.compile!(fields)
end
