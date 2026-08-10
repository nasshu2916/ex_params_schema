defmodule ExParamsSchema.Schema.DefaultsTest do
  use ExUnit.Case, async: true

  doctest ExParamsSchema.Schema.Defaults

  alias ExParamsSchema.Definition
  alias ExParamsSchema.Definition.Field
  alias ExParamsSchema.Schema.{Defaults, JsonSchema}

  describe "normalize!/2" do
    test "defaultを型変換し、defaultのないfieldは変更しない" do
      row_fields = [
        {:count, :integer, [default: "2", minimum: 1]},
        {:label, :string, []}
      ]

      assert normalize(row_fields) == [
               %Field{
                 name: :count,
                 type: :integer,
                 options: [
                   default: 2,
                   minimum: 1
                 ]
               },
               %Field{
                 name: :label,
                 type: :string,
                 options: []
               }
             ]
    end

    test "objectとarrayのdefaultを再帰的に型変換する" do
      fields =
        normalize([
          {:payload, %{published_on: {:date, [default: "2026-07-22"]}, count: {:integer, [default: "3"]}},
           [default: %{"published_on" => "2026-07-22", "count" => "3"}]},
          {:channels, [{:integer, [minimum: 1]}], [default: ["2"]]}
        ])

      payload = Enum.find(fields, &(&1.name == :payload))
      channels = Enum.find(fields, &(&1.name == :channels))
      {:object, payload_fields} = payload.type

      assert Keyword.fetch!(payload.options, :default) ==
               %{published_on: ~D[2026-07-22], count: 3}

      assert Enum.find(payload_fields, &(&1.name == :published_on)).options ==
               [default: ~D[2026-07-22]]

      assert Enum.find(payload_fields, &(&1.name == :count)).options == [default: 3]

      assert %{
               type: {:array, :integer, [minimum: 1]},
               options: [default: [2]]
             } = channels
    end

    test "型変換できないdefaultとJSON Schema制約を満たさないdefaultをパス付きで拒否する" do
      assert_raise ArgumentError, ~r/invalid default at count: "invalid"/, fn ->
        normalize([{:count, :integer, [default: "invalid"]}])
      end

      assert_raise ArgumentError, ~r/invalid default at payload.count: "0"/, fn ->
        normalize([{:payload, %{count: {:integer, [default: "0", minimum: 1]}}, []}])
      end

      assert_raise ArgumentError, ~r/invalid default at channels: \["0"\]/, fn ->
        normalize([{:channels, [{:integer, [minimum: 1]}], [default: ["0"]]}])
      end
    end

    test "JSON Pointerをエスケープするフィールド名でも対応するfragmentを検証する" do
      assert_raise ArgumentError, ~r/invalid default at a\/b~c: "0"/, fn ->
        normalize([{:"a/b~c", :integer, [default: "0", minimum: 1]}])
      end
    end
  end

  defp normalize(definitions) do
    fields = Definition.compile_fields!(definitions)
    {json_schema, _errors} = JsonSchema.build(fields, false)
    schema = ExJsonSchema.Schema.resolve(json_schema)

    Defaults.normalize!(fields, schema)
  end
end
