defmodule ExParamsSchema.Schema.ExJsonSchemaCompatibilityTest do
  use ExUnit.Case, async: true

  alias ExParamsSchema.Schema
  alias ExParamsSchema.Schema.Validator

  test "formatの検証結果を固定する" do
    schema = compile_schema(email: {:string, format: "email", error: :invalid_email})

    assert :ok = Validator.validate(schema, %{"email" => "user@example.com"})
    assert {:error, :invalid_email} = Validator.validate(schema, %{"email" => "not-an-email"})
  end

  test "anyOfとnotの論理制約の検証結果を固定する" do
    schema =
      compile_schema(
        value:
          {:any,
           json_schema: %{
             "anyOf" => [
               %{"type" => "integer", "minimum" => 1},
               %{"type" => "string", "minLength" => 2}
             ],
             "not" => %{"const" => 0}
           },
           error: :invalid_value}
      )

    assert :ok = Validator.validate(schema, %{"value" => 1})
    assert :ok = Validator.validate(schema, %{"value" => "ok"})
    assert {:error, :invalid_value} = Validator.validate(schema, %{"value" => 0})
    assert {:error, :invalid_value} = Validator.validate(schema, %{"value" => "x"})
  end

  test "JSON Pointerをエスケープするerror pathをフィールドerrorへ対応付ける" do
    schema =
      Schema.compile!([
        {:"a/b~c", :integer, [minimum: 1, error: :invalid_escaped]},
        {:later, :integer, [minimum: 1, error: :invalid_later]}
      ])

    assert schema.json_schema == %{
             "type" => "object",
             "properties" => %{
               "a/b~c" => %{"type" => "integer", "minimum" => 1},
               "later" => %{"type" => "integer", "minimum" => 1}
             },
             "required" => ["a/b~c", "later"],
             "$schema" => "http://json-schema.org/draft-07/schema#"
           }

    assert {:error, :invalid_escaped} =
             Validator.validate(schema, %{"a/b~c" => 0, "later" => 0})
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
