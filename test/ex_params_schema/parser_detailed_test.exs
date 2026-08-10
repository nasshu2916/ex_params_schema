defmodule ExParamsSchema.ParserDetailedTest do
  use ExUnit.Case, async: true

  doctest ExParamsSchema.Parser

  test "通常のparseと同じエラー理由でpath・制約・複数エラーを返す" do
    schema = validation_schema()

    params = %{
      "first" => "0",
      "payload" => %{"count" => "0"},
      "entries" => [%{"value" => "0"}]
    }

    assert {:error, :invalid_first} = ExParamsSchema.parse(params, schema)

    assert {:error,
            [
              %ExParamsSchema.ValidationError{
                path: ["first"],
                keyword: :minimum,
                reason: :invalid_first,
                details: %{expected: 1, exclusive?: false}
              },
              %ExParamsSchema.ValidationError{
                path: ["payload", "count"],
                keyword: :minimum,
                reason: :invalid_count,
                details: %{expected: 1, exclusive?: false}
              },
              %ExParamsSchema.ValidationError{
                path: ["entries", 0, "value"],
                keyword: :minimum,
                reason: :invalid_entry_value,
                details: %{expected: 1, exclusive?: false}
              }
            ]} = ExParamsSchema.parse_detailed(params, schema)
  end

  test "型変換エラーにもフィールドのpathと既存reasonを付与する" do
    schema = validation_schema()

    assert {:error,
            [
              %ExParamsSchema.ValidationError{
                path: ["first"],
                keyword: :cast,
                reason: :invalid_first
              }
            ]} = ExParamsSchema.parse_detailed(%{"first" => "invalid"}, schema)
  end

  test "ネストしたobjectとarrayの型変換エラーに完全なpathを付与する" do
    schema = validation_schema()

    assert {:error,
            [
              %ExParamsSchema.ValidationError{
                path: ["payload", "count"],
                keyword: :cast,
                reason: :invalid_count
              }
            ]} =
             ExParamsSchema.parse_detailed(
               %{
                 "first" => "1",
                 "payload" => %{"count" => "invalid"},
                 "entries" => [%{"value" => "1"}]
               },
               schema
             )

    assert {:error,
            [
              %ExParamsSchema.ValidationError{
                path: ["entries", 0, "value"],
                keyword: :cast,
                reason: :invalid_entry_value
              }
            ]} =
             ExParamsSchema.parse_detailed(
               %{
                 "first" => "1",
                 "payload" => %{"count" => "1"},
                 "entries" => [%{"value" => "invalid"}]
               },
               schema
             )
  end

  test "通常のparseはネストした型変換エラーのreasonを返す" do
    schema = validation_schema()

    assert {:error, :invalid_count} =
             ExParamsSchema.parse(
               %{
                 "first" => "1",
                 "payload" => %{"count" => "invalid"},
                 "entries" => [%{"value" => "1"}]
               },
               schema
             )
  end

  test "スラッシュとチルダを含むフィールド名を1つのpathとして返す" do
    name = String.to_atom("a/b~c")
    schema = ExParamsSchema.compile!(%{name => {:integer, minimum: 1, error: :invalid_escaped}})

    assert {:error,
            [
              %ExParamsSchema.ValidationError{
                path: ["a/b~c"],
                keyword: :minimum,
                reason: :invalid_escaped
              }
            ]} = ExParamsSchema.parse_detailed(%{"a/b~c" => "0"}, schema)
  end

  test "strict modeの未知キーをadditional_propertiesエラーとして返す" do
    fields = ExParamsSchema.Definition.compile_fields!([{:count, :integer, []}])
    schema = %ExParamsSchema.Schema{fields: fields, strict: true}

    assert {:error,
            [
              %ExParamsSchema.ValidationError{
                path: ["extra"],
                keyword: :additional_properties,
                reason: {:unknown_param, "extra"},
                details: %{key: "extra"}
              }
            ]} = ExParamsSchema.Parser.parse_detailed(%{"count" => "1", "extra" => true}, schema)
  end

  test "strict modeで既知キーだけなら詳細parseを継続する" do
    fields = ExParamsSchema.Definition.compile_fields!([{:count, :integer, []}])
    schema = ExParamsSchema.Schema.compile!(fields, true)

    assert {:ok, %{count: 1}} = ExParamsSchema.Parser.parse_detailed(%{"count" => "1"}, schema)
  end

  test "strict modeのatomと任意の未知キーを文字列pathとして返す" do
    fields = ExParamsSchema.Definition.compile_fields!([{:count, :integer, []}])
    schema = %ExParamsSchema.Schema{fields: fields, strict: true}

    assert {:error, [%ExParamsSchema.ValidationError{path: ["extra"], reason: {:unknown_param, :extra}}]} =
             ExParamsSchema.Parser.parse_detailed(%{"count" => "1", extra: true}, schema)

    assert {:error, [%ExParamsSchema.ValidationError{path: ["123"], reason: {:unknown_param, 123}}]} =
             ExParamsSchema.Parser.parse_detailed(%{"count" => "1", 123 => true}, schema)
  end

  test "nested strict objectの未知キーも完全なpathとadditional_propertiesを返す" do
    schema =
      ExParamsSchema.compile!(%{
        profile: {%{name: :string}, strict: true, error: :invalid_profile}
      })

    params = %{"profile" => %{"name" => "Ada", "extra" => true}}

    assert {:error,
            [
              %ExParamsSchema.ValidationError{
                path: ["profile", "extra"],
                keyword: :additional_properties,
                reason: :invalid_profile,
                details: %{key: "extra"}
              }
            ]} = ExParamsSchema.parse_detailed(params, schema)

    assert {:error, :invalid_profile} = ExParamsSchema.parse(params, schema)
  end

  test "array内のstrict objectの未知キーにも配列添字を含むpathを返す" do
    item_fields = ExParamsSchema.Definition.compile_fields!([{:name, :string, []}])

    schema =
      ExParamsSchema.Schema.compile!([
        %ExParamsSchema.Definition.Field{
          name: :entries,
          type: {:array, {:object, item_fields}, [strict: true]},
          options: [error: :invalid_entries]
        }
      ])

    assert {:error,
            [
              %ExParamsSchema.ValidationError{
                path: ["entries", 0, "extra"],
                keyword: :additional_properties,
                reason: :invalid_entries,
                details: %{key: "extra"}
              }
            ]} =
             ExParamsSchema.parse_detailed(
               %{"entries" => [%{"name" => "Ada", "extra" => true}]},
               schema
             )
  end

  defp validation_schema do
    ExParamsSchema.Schema.compile!([
      {:first, :integer, minimum: 1, error: :invalid_first},
      {:payload, %{count: {:integer, minimum: 1, error: :invalid_count}}, error: :invalid_payload},
      {:entries, [%{value: {:integer, minimum: 1, error: :invalid_entry_value}}], error: :invalid_entries}
    ])
  end
end
