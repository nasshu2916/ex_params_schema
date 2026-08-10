defmodule ExParamsSchema.Schema.JsonSchemaTest do
  use ExUnit.Case, async: true

  alias ExParamsSchema.Definition
  alias ExParamsSchema.Schema.JsonSchema

  defmodule MapSchemaType do
    @behaviour ExParamsSchema.Type

    @impl true
    def cast(value, _options), do: {:ok, value}

    @impl true
    def to_json(value, _options), do: value

    @impl true
    def json_schema(_options), do: %{"type" => "string", "format" => "uuid"}
  end

  defmodule BooleanSchemaType do
    @behaviour ExParamsSchema.Type

    @impl true
    def cast(value, _options), do: {:ok, value}

    @impl true
    def to_json(value, _options), do: value

    @impl true
    def json_schema(_options), do: false
  end

  defmodule AcceptingBooleanSchemaType do
    @behaviour ExParamsSchema.Type

    @impl true
    def cast(value, _options), do: {:ok, value}

    @impl true
    def to_json(value, _options), do: value

    @impl true
    def json_schema(_options), do: true
  end

  describe "build/2" do
    test "すべてのスカラー型と日付型をJSON Schemaへ変換する" do
      {schema, errors} =
        build([
          {:anything, :any, []},
          {:enabled, :boolean, []},
          {:ratio, :float, []},
          {:count, :integer, []},
          {:empty, :null, []},
          {:amount, :number, []},
          {:label, :string, []},
          {:published_on, :date, []},
          {:published_at, :datetime, []}
        ])

      assert schema["properties"] == %{
               "anything" => %{},
               "enabled" => %{"type" => "boolean"},
               "ratio" => %{"type" => "number"},
               "count" => %{"type" => "integer"},
               "empty" => %{"type" => "null"},
               "amount" => %{"type" => "number"},
               "label" => %{"type" => "string"},
               "published_on" => %{"type" => "string", "format" => "date"},
               "published_at" => %{"type" => "string", "format" => "date-time"}
             }

      assert schema["required"] == [
               "anything",
               "enabled",
               "ratio",
               "count",
               "empty",
               "amount",
               "label",
               "published_on",
               "published_at"
             ]

      assert errors == [
               {["anything"], {:invalid_param, :anything}, 0},
               {["enabled"], {:invalid_param, :enabled}, 1},
               {["ratio"], {:invalid_param, :ratio}, 2},
               {["count"], {:invalid_param, :count}, 3},
               {["empty"], {:invalid_param, :empty}, 4},
               {["amount"], {:invalid_param, :amount}, 5},
               {["label"], {:invalid_param, :label}, 6},
               {["published_on"], {:invalid_param, :published_on}, 7},
               {["published_at"], {:invalid_param, :published_at}, 8}
             ]
    end

    test "標準制約、enum、in、nullable、optionalを反映する" do
      {schema, _errors} =
        build([
          {:count, :integer, [minimum: 1, maximum: 3]},
          {:label, :string, [min_length: 2, max_length: 4, pattern: "^[a-z]+$", format: "email"]},
          {:items, [:string], [min_items: 1, max_items: 2, unique_items: true]},
          {:mode, {:enum, [:draft, :published]}, [nullable: true]},
          {:level, :integer, [in: 1..2, nullable: true]},
          {:choice, :string, [enum: ["first", "second"], nullable: true]},
          {:optional, :string, [optional: true]}
        ])

      assert schema["properties"] == %{
               "count" => %{"type" => "integer", "minimum" => 1, "maximum" => 3},
               "label" => %{
                 "type" => "string",
                 "minLength" => 2,
                 "maxLength" => 4,
                 "pattern" => "^[a-z]+$",
                 "format" => "email"
               },
               "items" => %{
                 "type" => "array",
                 "items" => %{"type" => "string"},
                 "minItems" => 1,
                 "maxItems" => 2,
                 "uniqueItems" => true
               },
               "mode" => %{"type" => ["string", "null"], "enum" => [nil, "draft", "published"]},
               "level" => %{"type" => ["integer", "null"], "enum" => [nil, 1, 2]},
               "choice" => %{"type" => ["string", "null"], "enum" => [nil, "first", "second"]},
               "optional" => %{"type" => "string"}
             }

      assert schema["required"] == ["count", "label", "items", "mode", "level", "choice"]
    end

    test "nullableなnull型と型を持たないスキーマはそのままにする" do
      {schema, _errors} = build([{:empty, :null, [nullable: true]}, {:anything, :any, [nullable: true]}])

      assert schema["properties"] == %{
               "empty" => %{"type" => "null"},
               "anything" => %{}
             }
    end

    test "arrayとobjectを再帰的に組み立て、strictをobjectだけへ適用する" do
      {schema, _errors} =
        build(
          [
            {:payload,
             %{
               name: :string,
               tags: {[{:string, nullable: true}], optional: true}
             }, [strict: true, nullable: true]}
          ],
          true
        )

      assert schema == %{
               "$schema" => "http://json-schema.org/draft-07/schema#",
               "type" => "object",
               "properties" => %{
                 "payload" => %{
                   "type" => ["object", "null"],
                   "properties" => %{
                     "name" => %{"type" => "string"},
                     "tags" => %{"type" => "array", "items" => %{"type" => ["string", "null"]}}
                   },
                   "required" => ["name"],
                   "additionalProperties" => false
                 }
               },
               "required" => ["payload"],
               "additionalProperties" => false
             }
    end

    test "custom type、json_schemaの真偽値とfragmentを反映する" do
      {schema, _errors} =
        build([
          {:identifier, {MapSchemaType, []}, [nullable: true, min_length: 36]},
          {:blocked, {BooleanSchemaType, []}, [nullable: true]},
          {:blocked_by_option, {AcceptingBooleanSchemaType, []}, [json_schema: false]},
          {:ignored, :string, [json_schema: false]},
          {:unchanged, :integer, [json_schema: true]},
          {:overridden, :integer,
           [
             minimum: 1,
             json_schema: %{type: "number", examples: [%{value: 1}], nested: %{const: true}}
           ]}
        ])

      assert schema["properties"] == %{
               "identifier" => %{
                 "type" => ["string", "null"],
                 "format" => "uuid",
                 "minLength" => 36
               },
               "blocked" => false,
               "blocked_by_option" => false,
               "ignored" => false,
               "unchanged" => %{"type" => "integer"},
               "overridden" => %{
                 "type" => "number",
                 "minimum" => 1,
                 "examples" => [%{"value" => 1}],
                 "nested" => %{"const" => true}
               }
             }
    end

    test "nullableはfragmentのtype配列へnullを重複なく追加する" do
      {schema, _errors} =
        build([
          {:value, :any, [json_schema: %{"type" => ["string", "integer"]}, nullable: true]}
        ])

      assert schema["properties"]["value"] == %{"type" => ["string", "integer", "null"]}
    end

    test "json_schema fragmentをネストしたmapまで再帰的にマージする" do
      {schema, _errors} =
        build([
          {:payload,
           %{
             title: :string,
             metadata: %{enabled: :boolean}
           },
           [
             json_schema: %{
               "properties" => %{
                 "title" => %{"minLength" => 1},
                 "metadata" => %{
                   "properties" => %{"enabled" => %{"const" => true}}
                 },
                 "source" => %{"type" => "string"}
               }
             }
           ]},
          {:tags, [:string], [json_schema: %{"items" => %{"minLength" => 2}}]}
        ])

      assert schema["properties"]["payload"]["properties"] == %{
               "title" => %{"type" => "string", "minLength" => 1},
               "metadata" => %{
                 "type" => "object",
                 "properties" => %{"enabled" => %{"type" => "boolean", "const" => true}},
                 "required" => ["enabled"]
               },
               "source" => %{"type" => "string"}
             }

      assert schema["properties"]["tags"]["items"] == %{"type" => "string", "minLength" => 2}
    end

    test "親子のerrorを継承し、array indexを含む宣言順のerror定義を返す" do
      {_, errors} =
        build([
          {:payload,
           %{
             count: :integer,
             label: {:string, error: :invalid_label}
           }, [error: :invalid_payload]},
          {:channels, [{:integer, error: :invalid_channel}], [error: :invalid_channels]}
        ])

      assert errors == [
               {["payload"], :invalid_payload, 0},
               {["payload", "count"], :invalid_payload, 2},
               {["payload", "label"], :invalid_label, 3},
               {["channels"], :invalid_channels, 4},
               {["channels", :index], :invalid_channel, 5}
             ]
    end
  end

  defp build(fields, strict \\ false) do
    fields
    |> Definition.compile_fields!()
    |> JsonSchema.build(strict)
  end
end
