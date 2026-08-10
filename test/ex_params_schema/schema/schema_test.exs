defmodule ExParamsSchema.SchemaTest do
  use ExUnit.Case, async: true

  doctest ExParamsSchema.Schema

  alias ExParamsSchema.Definition.Field
  alias ExParamsSchema.Schema
  alias ExParamsSchema.Schema.Validator

  defmodule BooleanSchemaType do
    @behaviour ExParamsSchema.Type

    @impl true
    def cast(value, _options), do: {:ok, value}

    @impl true
    def to_json(value, _options), do: value

    @impl true
    def json_schema(_options), do: false
  end

  test "標準制約をJSON Schemaで検証する" do
    schema =
      compile_schema(
        count: {:integer, minimum: 1, maximum: 3, error: :invalid_count},
        label: {:string, min_length: 2, max_length: 4, error: :invalid_label},
        items: {[{:integer, minimum: 1}], min_items: 1, max_items: 2, error: :invalid_items}
      )

    assert :ok =
             Validator.validate(schema, %{
               "count" => 2,
               "label" => "日本",
               "items" => [1, 2]
             })

    assert {:error, :invalid_count} = valid_data(schema, %{"count" => 0})
    assert {:error, :invalid_label} = valid_data(schema, %{"label" => "x"})
    assert {:error, :invalid_items} = valid_data(schema, %{"items" => []})
  end

  test "nullable、optional、enum、inをJSON Schemaへ変換する" do
    schema =
      compile_schema(
        ratio: {:number, nullable: true, error: :invalid_ratio},
        label: {:string, optional: true, error: :invalid_label},
        mode: {:string, enum: ["merge", "replace"], error: :invalid_mode},
        level: {:integer, in: 1..3, error: :invalid_level}
      )

    assert :ok = Validator.validate(schema, %{"ratio" => nil, "mode" => "merge", "level" => 1})

    assert {:error, :invalid_mode} =
             Validator.validate(schema, %{"ratio" => nil, "mode" => "remove", "level" => 1})

    assert {:error, :invalid_level} =
             Validator.validate(schema, %{"ratio" => nil, "mode" => "merge", "level" => 4})
  end

  test "atom enumをJSON Schema検証用の文字列へ射影する" do
    schema = compile_schema(mode: {{:enum, [:merge, :replace]}, error: :invalid_mode})

    assert %{"mode" => "merge"} = Schema.validation_data(schema, %{mode: :merge})
    assert :ok = Validator.validate(schema, %{"mode" => "merge"})
  end

  test "生成したJSON Schema Draft 7を返す" do
    schema = compile_schema(count: {:integer, minimum: 1}, label: {:string, optional: true})

    assert ExParamsSchema.json_schema(schema) == %{
             "$schema" => "http://json-schema.org/draft-07/schema#",
             "type" => "object",
             "properties" => %{
               "count" => %{"type" => "integer", "minimum" => 1},
               "label" => %{"type" => "string"}
             },
             "required" => ["count"]
           }
  end

  test "fieldsからJSON Schema Draft 7を生成する" do
    fields = [{:identifier, :integer, [minimum: 1]}]

    assert Schema.json_schema(fields) == %{
             "$schema" => "http://json-schema.org/draft-07/schema#",
             "type" => "object",
             "properties" => %{
               "identifier" => %{"type" => "integer", "minimum" => 1}
             },
             "required" => ["identifier"]
           }
  end

  test "コンパイル済みfieldsからJSON Schemaを再生成する" do
    schema = compile_schema(count: :integer)
    assert Schema.json_schema(schema.fields) == schema.json_schema
  end

  test "コンパイル済みスキーマでもstrict指定をJSON Schemaへ反映する" do
    schema = compile_schema(count: :integer)

    assert Schema.json_schema(schema, true)["additionalProperties"] == false
    refute Map.has_key?(Schema.json_schema(schema, false), "additionalProperties")
  end

  test "strictでコンパイル済みのスキーマは指定を省略しても生成済みJSON Schemaを返す" do
    schema = Schema.compile!([{:count, :integer, []}], true)

    assert Schema.json_schema(schema) == schema.json_schema
    assert Schema.json_schema(schema)["additionalProperties"] == false
  end

  test "フィールド定義とコンパイル済みフィールドの混在を拒否する" do
    compiled_field = %Field{name: :compiled, type: :integer}

    assert_raise ArgumentError, ~r/mixed lists are not supported/, fn ->
      Schema.compile!([compiled_field, {:raw, :string, []}])
    end

    assert_raise ArgumentError, ~r/mixed lists are not supported/, fn ->
      Schema.json_schema([compiled_field, {:raw, :string, []}])
    end
  end

  test "float、nullable、json_schema true、boolean custom schemaを生成する" do
    schema =
      compile_schema(
        ratio: :float,
        empty: {:null, nullable: true},
        anything: {:any, nullable: true, json_schema: true},
        forbidden: {{BooleanSchemaType, []}, optional: true}
      )

    assert schema.json_schema["properties"] == %{
             "ratio" => %{"type" => "number"},
             "empty" => %{"type" => "null"},
             "anything" => %{},
             "forbidden" => false
           }
  end

  test "strict modeをadditionalProperties falseへ変換する" do
    schema =
      ExParamsSchema.compile!(
        %{profile: {%{name: :string}, strict: true}},
        strict: true
      )

    assert ExParamsSchema.json_schema(schema) == %{
             "$schema" => "http://json-schema.org/draft-07/schema#",
             "type" => "object",
             "properties" => %{
               "profile" => %{
                 "type" => "object",
                 "properties" => %{"name" => %{"type" => "string"}},
                 "required" => ["name"],
                 "additionalProperties" => false
               }
             },
             "required" => ["profile"],
             "additionalProperties" => false
           }
  end

  test "map形式の定義でもstrict modeのJSON Schemaを生成する" do
    assert ExParamsSchema.json_schema(%{count: :integer}, strict: true) == %{
             "$schema" => "http://json-schema.org/draft-07/schema#",
             "type" => "object",
             "properties" => %{"count" => %{"type" => "integer"}},
             "required" => ["count"],
             "additionalProperties" => false
           }
  end

  test "日付・日時をISO 8601文字列へ射影してJSON Schemaで検証する" do
    schema = compile_schema(published_on: :date, published_at: :datetime)

    assert %{"published_on" => "2026-07-22", "published_at" => "2026-07-22T03:04:05Z"} =
             Schema.validation_data(schema, %{
               published_on: ~D[2026-07-22],
               published_at: ~U[2026-07-22 03:04:05Z]
             })

    assert :ok =
             Validator.validate(schema, %{
               "published_on" => "2026-07-22",
               "published_at" => "2026-07-22T03:04:05Z"
             })
  end

  test "ネストしたフィールドとlist itemのerrorを返す" do
    schema =
      compile_schema(
        point: {%{x: {:integer, minimum: 1, error: :invalid_x}}, error: :invalid_point},
        channels: {[{:integer, minimum: 1, error: :invalid_channel}], error: :invalid_channels}
      )

    assert {:error, :invalid_x} =
             Validator.validate(schema, %{"point" => %{"x" => 0}, "channels" => [1]})

    assert {:error, :invalid_channel} =
             Validator.validate(schema, %{"point" => %{"x" => 1}, "channels" => [0]})
  end

  test "複数のエラーでは宣言順が先のフィールドを返す" do
    schema =
      compile_schema(
        first: {:integer, minimum: 1, error: :invalid_first},
        second: {:integer, minimum: 1, error: :invalid_second}
      )

    assert {:error, :invalid_first} =
             Validator.validate(schema, %{"first" => 0, "second" => 0})
  end

  test "JSON Pointerをエスケープするフィールド名でも最も近いerrorを返す" do
    schema =
      Schema.compile!([
        {:"a/b~c", :integer, [minimum: 1, error: :invalid_escaped]},
        {:later, :integer, [minimum: 1, error: :invalid_later]}
      ])

    assert {:error, :invalid_escaped} =
             Validator.validate(schema, %{"a/b~c" => 0, "later" => 0})
  end

  test "JSON Pointerから最も近いエラー定義と解決済みパスを取得する" do
    schema =
      Schema.compile!([
        {:payload, %{entries: {[{:integer, minimum: 1}], error: :invalid_entries}}, []}
      ])

    assert {3, :invalid_entries, ["payload", "entries", 3, "value"]} =
             Schema.resolve_error_path(schema, "#/payload/entries/3/value")

    assert nil == Schema.resolve_error_path(schema, "invalid")
  end

  test "非推奨APIでもJSON Pointerに対応するerrorの順序と理由を返す" do
    schema =
      Schema.compile!([
        {:count, :integer, [minimum: 1, error: :invalid_count]}
      ])

    function_name = :error_for_path

    assert {0, :invalid_count} == apply(Schema, function_name, [schema, "#/count"])
    assert nil == apply(Schema, function_name, [schema, "#/unknown"])
  end

  test "ネストした複数のJSON Schemaエラーでは最も近いerrorと宣言順を返す" do
    schema =
      compile_schema(
        first: {:integer, minimum: 1, error: :invalid_first},
        payload:
          {%{
             count: {:integer, minimum: 1, error: :invalid_count},
             limit: {:integer, minimum: 1, error: :invalid_limit}
           }, error: :invalid_payload}
      )

    assert {:error, :invalid_first} =
             Validator.validate(schema, %{
               "first" => 0,
               "payload" => %{"count" => 0, "limit" => 0}
             })

    assert {:error, :invalid_count} =
             Validator.validate(schema, %{
               "first" => 1,
               "payload" => %{"count" => 0, "limit" => 0}
             })
  end

  test "defaultを定義時に型変換して制約検証する" do
    schema = compile_schema(count: {:integer, default: "2", minimum: 1})

    assert [%ExParamsSchema.Definition.Field{name: :count, type: :integer, options: options}] = schema.fields
    assert Keyword.fetch!(options, :default) == 2

    assert_raise ArgumentError, ~r/invalid default at count/, fn ->
      compile_schema(count: {:integer, default: "0", minimum: 1})
    end
  end

  test "ネストしたdefaultを型変換し、対応するJSON Schema fragmentで検証する" do
    schema =
      compile_schema(
        payload:
          {%{
             published_on: {:date, default: "2026-07-22"},
             count: {:integer, default: "2", minimum: 1}
           }, default: %{"published_on" => "2026-07-22", "count" => "2"}}
      )

    [payload] = schema.fields
    {:object, fields} = payload.type
    published_on = Enum.find(fields, &(&1.name == :published_on))
    count = Enum.find(fields, &(&1.name == :count))

    assert Keyword.fetch!(published_on.options, :default) == ~D[2026-07-22]
    assert Keyword.fetch!(count.options, :default) == 2
    assert Keyword.fetch!(payload.options, :default) == %{published_on: ~D[2026-07-22], count: 2}

    assert_raise ArgumentError, ~r/invalid default at payload.count/, fn ->
      compile_schema(payload: %{count: {:integer, default: "0", minimum: 1}})
    end
  end

  test "patternとformatを文字列制約として検証する" do
    schema =
      compile_schema(
        code: {:string, pattern: "^[A-Z]{3}$", error: :invalid_code},
        email: {:string, format: "email", error: :invalid_email}
      )

    assert :ok = Validator.validate(schema, %{"code" => "ABC", "email" => "user@example.com"})

    assert {:error, :invalid_code} =
             Validator.validate(schema, %{"code" => "abc", "email" => "user@example.com"})

    assert {:error, :invalid_email} =
             Validator.validate(schema, %{"code" => "ABC", "email" => "not-an-email"})
  end

  test "unique_itemsを配列制約として検証する" do
    schema =
      compile_schema(items: {[{:integer, minimum: 1}], unique_items: true, error: :invalid_items})

    assert :ok = Validator.validate(schema, %{"items" => [1, 2]})
    assert {:error, :invalid_items} = Validator.validate(schema, %{"items" => [1, 1]})
  end

  test "json_schemaで数値と文字列のDraft 7制約を追加する" do
    schema =
      compile_schema(
        step: {:number, json_schema: %{"multipleOf" => 0.5, "exclusiveMinimum" => 1}, error: :invalid_step},
        code: {:string, json_schema: %{"pattern" => "^[A-Z]+$", "format" => "hostname"}, error: :invalid_code}
      )

    assert :ok = Validator.validate(schema, %{"step" => 1.5, "code" => "EXAMPLE"})

    assert {:error, :invalid_step} =
             Validator.validate(schema, %{"step" => 1.0, "code" => "EXAMPLE"})

    assert {:error, :invalid_code} =
             Validator.validate(schema, %{"step" => 1.5, "code" => "lower"})
  end

  test "json_schema fragmentのatom keyをネストしても文字列keyへ正規化する" do
    schema =
      compile_schema(
        payload:
          {:any,
           json_schema: %{
             type: "object",
             properties: %{state: %{type: "string", enum: ["active"]}},
             required: ["state"]
           }}
      )

    assert schema.json_schema["properties"]["payload"] == %{
             "type" => "object",
             "properties" => %{"state" => %{"type" => "string", "enum" => ["active"]}},
             "required" => ["state"]
           }
  end

  test "json_schemaで配列、object、論理制約を追加する" do
    schema =
      compile_schema(
        tuple:
          {:any,
           json_schema: %{
             "type" => "array",
             "items" => [%{"type" => "integer"}, %{"type" => "string"}],
             "additionalItems" => false,
             "uniqueItems" => true,
             "contains" => %{"type" => "integer"}
           },
           error: :invalid_tuple},
        payload:
          {:any,
           json_schema: %{
             "type" => "object",
             "minProperties" => 1,
             "maxProperties" => 2,
             "additionalProperties" => false,
             "properties" => %{"kind" => %{"const" => "fixed"}},
             "required" => ["kind"]
           },
           error: :invalid_payload},
        choice:
          {:any,
           json_schema: %{
             "anyOf" => [%{"type" => "integer"}, %{"type" => "string", "minLength" => 2}],
             "not" => %{"const" => 0}
           },
           error: :invalid_choice}
      )

    assert :ok =
             Validator.validate(schema, %{
               "tuple" => [1, "one"],
               "payload" => %{"kind" => "fixed"},
               "choice" => "ok"
             })

    assert {:error, :invalid_tuple} =
             Validator.validate(schema, %{
               "tuple" => [1, "one", 2],
               "payload" => %{"kind" => "fixed"},
               "choice" => "ok"
             })

    assert {:error, :invalid_payload} =
             Validator.validate(schema, %{
               "tuple" => [1, "one"],
               "payload" => %{"kind" => "fixed", "extra" => 1},
               "choice" => "ok"
             })

    assert {:error, :invalid_choice} =
             Validator.validate(schema, %{
               "tuple" => [1, "one"],
               "payload" => %{"kind" => "fixed"},
               "choice" => 0
             })
  end

  test "json_schemaのboolean schemaを解決する" do
    schema =
      Schema.compile!([
        {:forbidden, :any, [json_schema: false, optional: true, error: :invalid_forbidden]}
      ])

    assert :ok = Validator.validate(schema, %{})
    assert {:error, :invalid_forbidden} = Validator.validate(schema, %{"forbidden" => nil})
  end

  test "対応するフィールドerrorがないJSON Schemaエラーは汎用エラーへ正規化する" do
    schema = compile_schema(count: {:integer, minimum: 1, error: :invalid_count})

    assert {:error, :invalid_params} =
             Validator.validate(%{schema | errors: []}, %{"count" => 0})
  end

  test "詳細エラーでは対応するフィールドerrorがないpathを汎用エラーとして返す" do
    schema = compile_schema(count: {:integer, minimum: 1, error: :invalid_count})

    assert {:error,
            [
              %ExParamsSchema.ValidationError{
                path: ["count"],
                keyword: :minimum,
                reason: :invalid_params,
                details: %{expected: 1, exclusive?: false}
              }
            ]} = Validator.validate_detailed(%{schema | errors: []}, %{"count" => 0})
  end

  test "必須フィールドの詳細エラーを返す" do
    schema = compile_schema(count: {:integer, error: :invalid_count})

    assert {:error,
            [
              %ExParamsSchema.ValidationError{
                path: ["count"],
                keyword: :required,
                reason: :invalid_count
              }
            ]} = Validator.validate_detailed(schema, %{})
  end

  test "複数の必須フィールド欠落を宣言順の詳細エラーへ展開する" do
    schema =
      compile_schema(
        first: {:integer, error: :invalid_first},
        second: {:string, error: :invalid_second}
      )

    assert {:error,
            [
              %ExParamsSchema.ValidationError{
                path: ["first"],
                keyword: :required,
                reason: :invalid_first,
                details: %{}
              },
              %ExParamsSchema.ValidationError{
                path: ["second"],
                keyword: :required,
                reason: :invalid_second,
                details: %{}
              }
            ]} = Validator.validate_detailed(schema, %{})
  end

  defp valid_data(schema, overrides) do
    %{"count" => 2, "label" => "good", "items" => [1]}
    |> Map.merge(overrides)
    |> then(&Validator.validate(schema, &1))
  end

  defp compile_schema(definitions) do
    fields =
      Enum.map(definitions, fn {name, definition} ->
        {type, options} = ExParamsSchema.Definition.normalize!(definition)
        {name, type, options}
      end)

    Schema.compile!(fields)
  end
end
