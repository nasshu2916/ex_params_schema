defmodule Mix.Tasks.ExParamsSchema.ExportJsonSchemaTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  defmodule ExampleParams do
    use ExParamsSchema

    defschema strict: true do
      field :identifier, :string,
        min_length: 3,
        pattern: "^[a-z]+-[0-9]+$",
        json_schema: %{"examples" => ["item-42"]}

      field :state, {:enum, [:draft, :published]}, nullable: true

      field :metadata,
            %{
              title: {:string, min_length: 1},
              tags: {[{:string, nullable: true}], optional: true}
            },
            strict: true,
            json_schema: %{
              "properties" => %{
                "title" => %{"examples" => ["Release notes"]}
              }
            }

      field :rules,
            [
              {%{code: {:string, pattern: "^[A-Z]+$"}, threshold: {:number, json_schema: %{"multipleOf" => 0.25}}},
               strict: true}
            ],
            min_items: 1,
            unique_items: true

      field :extra, :any,
        optional: true,
        json_schema: %{
          "oneOf" => [
            %{"type" => "string"},
            %{"type" => "integer"}
          ]
        }
    end
  end

  setup do
    Mix.Task.reenable("ex_params_schema.export_json_schema")
    :ok
  end

  test "json_schema optionを含む複雑なschemaをJSONとして出力する" do
    schema =
      export_schema("Mix.Tasks.ExParamsSchema.ExportJsonSchemaTest.ExampleParams")

    assert schema == ExampleParams.json_schema()
    assert schema["additionalProperties"] == false
    assert schema["required"] == ["identifier", "state", "metadata", "rules"]

    assert schema["properties"]["identifier"] == %{
             "examples" => ["item-42"],
             "minLength" => 3,
             "pattern" => "^[a-z]+-[0-9]+$",
             "type" => "string"
           }

    assert schema["properties"]["state"] == %{
             "enum" => [nil, "draft", "published"],
             "type" => ["string", "null"]
           }

    assert schema["properties"]["metadata"] == %{
             "additionalProperties" => false,
             "properties" => %{
               "tags" => %{"items" => %{"type" => ["string", "null"]}, "type" => "array"},
               "title" => %{"examples" => ["Release notes"], "minLength" => 1, "type" => "string"}
             },
             "required" => ["title"],
             "type" => "object"
           }

    assert schema["properties"]["rules"] == %{
             "items" => %{
               "additionalProperties" => false,
               "properties" => %{
                 "code" => %{"pattern" => "^[A-Z]+$", "type" => "string"},
                 "threshold" => %{"multipleOf" => 0.25, "type" => "number"}
               },
               "required" => ["code", "threshold"],
               "type" => "object"
             },
             "minItems" => 1,
             "type" => "array",
             "uniqueItems" => true
           }

    assert schema["properties"]["extra"] == %{
             "oneOf" => [%{"type" => "string"}, %{"type" => "integer"}]
           }
  end

  test "--outputでJSON Schemaをファイルに書き出す" do
    output_path =
      Path.join(
        System.tmp_dir!(),
        "ex_params_schema/export_json_schema_#{System.unique_integer([:positive])}.json"
      )

    on_exit(fn -> File.rm(output_path) end)

    capture_io(fn ->
      Mix.Task.run("ex_params_schema.export_json_schema", [
        "Mix.Tasks.ExParamsSchema.ExportJsonSchemaTest.ExampleParams",
        "--output",
        output_path
      ])
    end)

    output_schema = Jason.decode!(File.read!(output_path))

    assert output_schema == ExampleParams.json_schema()
    assert output_schema["properties"]["rules"]["items"]["type"] == "object"
  end

  test "json_schema/0を持たないモジュールを拒否する" do
    assert_raise Mix.Error,
                 ~r/must define json_schema\/0 through use ExParamsSchema/,
                 fn ->
                   Mix.Task.run("ex_params_schema.export_json_schema", ["ExParamsSchema"])
                 end
  end

  defp export_schema(module_name) do
    output =
      capture_io(fn ->
        Mix.Task.run("ex_params_schema.export_json_schema", [module_name])
      end)

    Jason.decode!(output)
  end
end
