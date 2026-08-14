defmodule Mix.Tasks.ExParamsSchema.GenerateSchemaTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  setup do
    Mix.Task.reenable("ex_params_schema.generate_schema")
    :ok
  end

  test "Draft 7 object schemaからdefschemaモジュールを生成する" do
    input_path = temporary_path("input.json")

    schema = %{
      "$schema" => "http://json-schema.org/draft-07/schema#",
      "type" => "object",
      "additionalProperties" => false,
      "properties" => %{
        "id" => %{"type" => "integer", "minimum" => 1},
        "display-name" => %{"type" => ["string", "null"], "minLength" => 1},
        "tags" => %{"type" => "array", "items" => %{"type" => "string"}, "minItems" => 1},
        "metadata" => %{
          "type" => "object",
          "additionalProperties" => false,
          "properties" => %{"enabled" => %{"type" => "boolean"}},
          "required" => ["enabled"]
        },
        "choice" => %{"type" => ["string", "integer"]}
      },
      "required" => ["id", "display-name", "tags", "metadata"]
    }

    File.write!(input_path, Jason.encode!(schema))
    on_exit(fn -> File.rm(input_path) end)

    source =
      capture_io(fn ->
        Mix.Task.run("ex_params_schema.generate_schema", [input_path, "GeneratedParams"])
      end)

    assert source =~ "defmodule GeneratedParams do"
    assert source =~ "field(:\"display-name\""
    assert source =~ "defschema(strict: true)"

    [{generated_module, _bytecode}] = Code.compile_string(source)
    generated_schema = generated_module.json_schema()
    assert generated_schema["properties"] == schema["properties"]
    assert MapSet.new(generated_schema["required"]) == MapSet.new(schema["required"])
    assert generated_schema["additionalProperties"] == false
  end

  test "--outputで生成モジュールを書き出す" do
    input_path = temporary_path("input.json")
    output_path = temporary_path("generated_params.ex")
    File.write!(input_path, Jason.encode!(%{"type" => "object", "properties" => %{}}))

    on_exit(fn ->
      File.rm(input_path)
      File.rm(output_path)
    end)

    output =
      capture_io(fn ->
        Mix.Task.run("ex_params_schema.generate_schema", [input_path, "OutputParams", "--output", output_path])
      end)

    assert output =~ "Wrote ExParamsSchema module to #{output_path}"
    assert File.read!(output_path) =~ "defmodule OutputParams do"
  end

  test "rootのadditionalPropertiesが未指定なら追加プロパティを拒否せず、required外のfieldをoptionalにする" do
    input_path = temporary_path("open_root.json")

    File.write!(
      input_path,
      Jason.encode!(%{
        "type" => "object",
        "properties" => %{
          "required_value" => %{"type" => "integer"},
          "optional_value" => %{"type" => "string"}
        },
        "required" => ["required_value"]
      })
    )

    on_exit(fn -> File.rm(input_path) end)

    source =
      capture_io(fn ->
        Mix.Task.run("ex_params_schema.generate_schema", [input_path, "OpenRootParams"])
      end)

    [{generated_module, _bytecode}] = Code.compile_string(source)
    generated_schema = generated_module.json_schema()

    refute Map.has_key?(generated_schema, "additionalProperties")
    assert generated_schema["required"] == ["required_value"]

    assert {:ok, params} = generated_module.parse(%{"required_value" => "1", "extra" => "accepted"})
    assert Map.from_struct(params) == %{required_value: 1, optional_value: nil}
  end

  test "object propertiesを持たないroot schemaを拒否する" do
    input_path = temporary_path("invalid.json")
    File.write!(input_path, Jason.encode!(%{"type" => "string"}))
    on_exit(fn -> File.rm(input_path) end)

    assert_raise ArgumentError, ~r/root must contain an object properties map/, fn ->
      Mix.Task.run("ex_params_schema.generate_schema", [input_path, "InvalidParams"])
    end
  end

  test "未対応のroot schemaを拒否する" do
    input_path = temporary_path("unsupported.json")
    File.write!(input_path, Jason.encode!(%{"$ref" => "#/definitions/user"}))
    on_exit(fn -> File.rm(input_path) end)

    assert_raise ArgumentError, ~r/root must contain an object properties map/, fn ->
      Mix.Task.run("ex_params_schema.generate_schema", [input_path, "UnsupportedParams"])
    end
  end

  test "Draft 7より古いJSON Schemaを拒否する" do
    input_path = temporary_path("draft_06.json")

    File.write!(
      input_path,
      Jason.encode!(%{
        "$schema" => "http://json-schema.org/draft-06/schema#",
        "type" => "object",
        "properties" => %{}
      })
    )

    on_exit(fn -> File.rm(input_path) end)

    assert_raise ArgumentError, ~r/unsupported JSON Schema version .*only Draft 7 is supported/, fn ->
      Mix.Task.run("ex_params_schema.generate_schema", [input_path, "DraftSixParams"])
    end
  end

  defp temporary_path(filename) do
    Path.join(
      System.tmp_dir!(),
      "ex_params_schema/generate_schema_#{System.unique_integer([:positive])}_#{filename}"
    )
  end
end
