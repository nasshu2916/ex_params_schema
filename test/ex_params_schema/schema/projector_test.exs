defmodule ExParamsSchema.Schema.ProjectorTest do
  use ExUnit.Case, async: true

  alias ExParamsSchema.Definition
  alias ExParamsSchema.Schema.Projector

  defmodule PrefixedIdentifier do
    @behaviour ExParamsSchema.Type

    @impl true
    def cast(value, _options), do: {:ok, value}

    @impl true
    def to_json(value, options), do: "#{Keyword.fetch!(options, :prefix)}#{value}"

    @impl true
    def json_schema(_options), do: %{"type" => "string"}
  end

  describe "project/2" do
    test "フィールド名を文字列キーにし、通常の値とnullableなnilを保持する" do
      fields =
        Definition.compile_fields!([
          {:count, :integer, []},
          {:enabled, :boolean, []},
          {:metadata, :any, []},
          {:note, :string, [nullable: true]}
        ])

      assert Projector.project(fields, %{
               count: 3,
               enabled: true,
               metadata: %{source: "form"},
               note: nil
             }) == %{
               "count" => 3,
               "enabled" => true,
               "metadata" => %{source: "form"},
               "note" => nil
             }
    end

    test "optionalなnilを省略し、値があるoptionalフィールドは保持する" do
      fields =
        Definition.compile_fields!([
          {:label, :string, [optional: true]},
          {:code, :string, [optional: true]}
        ])

      assert Projector.project(fields, %{label: nil, code: "A-1"}) == %{"code" => "A-1"}
    end

    test "objectとarrayを再帰的に射影する" do
      fields =
        fields(
          payload: %{
            published_on: :date,
            mode: {:enum, [:merge, :replace]},
            identifier: {PrefixedIdentifier, [prefix: "id:"]},
            omitted: {:string, optional: true}
          },
          events: [
            %{
              occurred_at: :datetime,
              modes: [{:enum, [:merge, :replace]}],
              identifiers: [{PrefixedIdentifier, [prefix: "id:"]}]
            }
          ]
        )

      assert Projector.project(fields, %{
               payload: %{
                 published_on: ~D[2026-07-22],
                 mode: :merge,
                 identifier: "123",
                 omitted: nil
               },
               events: [
                 %{
                   occurred_at: ~U[2026-07-22 03:04:05Z],
                   modes: [:replace, :merge],
                   identifiers: ["456", "789"]
                 }
               ]
             }) == %{
               "payload" => %{
                 "published_on" => "2026-07-22",
                 "mode" => "merge",
                 "identifier" => "id:123"
               },
               "events" => [
                 %{
                   "occurred_at" => "2026-07-22T03:04:05Z",
                   "modes" => ["replace", "merge"],
                   "identifiers" => ["id:456", "id:789"]
                 }
               ]
             }
    end
  end

  describe "project_value/2" do
    test "nilは型にかかわらずnilのまま返す" do
      assert Projector.project_value(:date, nil) == nil
      assert Projector.project_value({:enum, [:merge]}, nil) == nil
      assert Projector.project_value({:array, :date, []}, [nil]) == [nil]
    end

    test "enum、custom type、date、datetimeをJSON互換値へ変換する" do
      assert Projector.project_value({:enum, [:merge]}, :merge) == "merge"

      assert Projector.project_value({:custom, PrefixedIdentifier, [prefix: "id:"]}, "123") ==
               "id:123"

      assert Projector.project_value(:date, ~D[2026-07-22]) == "2026-07-22"

      assert Projector.project_value(:datetime, ~U[2026-07-22 03:04:05Z]) ==
               "2026-07-22T03:04:05Z"
    end

    test "特別な射影規則を持たない型の値をそのまま返す" do
      value = %{nested: [1, true, nil]}

      assert Projector.project_value(:any, value) == value
      assert Projector.project_value(:null, nil) == nil
    end
  end

  defp fields(definitions) do
    definitions
    |> Enum.map(fn {name, definition} -> {name, definition, []} end)
    |> Definition.compile_fields!()
  end
end
