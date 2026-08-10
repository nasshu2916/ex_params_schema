defmodule ExParamsSchema.Definition.ValidatorTest do
  use ExUnit.Case, async: true

  alias ExParamsSchema.Definition.Validator

  defmodule CustomType do
    @behaviour ExParamsSchema.Type

    @impl true
    def cast(value, _options), do: {:ok, value}

    @impl true
    def to_json(value, _options), do: value

    @impl true
    def json_schema(_options), do: %{}
  end

  test "各型の有効な定義を検証する" do
    assert Validator.validate_definition!(:integer, [minimum: 0], ["count"], :field) == :ok
    assert Validator.validate_definition!({:enum, [:draft, :published]}, [], ["status"], :field) == :ok

    assert Validator.validate_definition!({:custom, CustomType, enabled: true}, [], ["price"], :field) ==
             :ok
  end

  test "フィールド名と option 形式の不正を拒否する" do
    assert_raise ArgumentError, ~r/schema field name must be an atom/, fn ->
      Validator.normalize_fields!([{"count", :integer, []}])
    end

    assert_raise ArgumentError, ~r/must be a keyword list/, fn ->
      Validator.normalize_fields!([{:count, :integer, [1]}])
    end
  end

  test "unsupported 型と不正な atom enum を拒否する" do
    assert_raise ArgumentError, ~r/unsupported type 123/, fn ->
      Validator.validate_definition!(123, [], ["value"], :field)
    end

    assert_raise ArgumentError, ~r/atom enum must contain one or more atoms/, fn ->
      Validator.validate_definition!({:enum, [:draft, "published"]}, [], ["status"], :field)
    end
  end

  test "フィールド名と入力キーの重複を拒否する" do
    assert Validator.validate_unique_field_names!([{:count, :integer, []}]) == :ok
    assert Validator.validate_unique_input_keys!([{:count, :integer, []}], []) == :ok

    assert_raise ArgumentError, ~r/schema field name :count is declared more than once/, fn ->
      Validator.validate_unique_field_names!([{:count, :integer, []}, {:count, :string, []}])
    end

    assert_raise ArgumentError, ~r/input key "value" is used by both fields :first and :second/, fn ->
      Validator.validate_unique_input_keys!(
        [{:first, :integer, source: "value"}, {:second, :integer, source: "value"}],
        []
      )
    end
  end

  test "フィールド群を正規化し、入力キーの重複を検証する" do
    assert Validator.normalize_fields!([
             {:status, {:enum, [:draft, :published]}, []},
             {:price, {CustomType, enabled: true}, [source: "price_cents"]},
             {:items, [:integer], [min_items: 1]}
           ]) == [
             {:status, {:enum, [:draft, :published]}, []},
             {:price, {:custom, CustomType, [enabled: true]}, [source: "price_cents"]},
             {:items, [:integer], [min_items: 1]}
           ]

    assert_raise ArgumentError, ~r/input key "value" is used by both fields :first and :second/, fn ->
      Validator.normalize_fields!([
        {:first, :integer, [source: "value"]},
        {:second, :string, [source: "value"]}
      ])
    end
  end

  test "custom type の callback と atom enum の制約を検証する" do
    assert_raise ArgumentError, ~r/custom type String must implement/, fn ->
      Validator.validate_definition!({:custom, String, []}, [], ["value"], :field)
    end

    assert_raise ArgumentError, ~r/cannot be used with :atom_enum/, fn ->
      Validator.validate_definition!({:enum, [:merge, :replace]}, [enum: [:merge]], ["mode"], :field)
    end
  end

  test "nested object 内の入力キー重複を拒否する" do
    assert_raise ArgumentError,
                 ~r/invalid schema at payload: input key "value" is used by both fields :first and :second/,
                 fn ->
                   Validator.validate_definition!(
                     %{first: {:integer, source: "value"}, second: {:integer, source: "value"}},
                     [],
                     ["payload"],
                     :field
                   )
                 end
  end

  test "配列の要素定義と入れ子 object を検証する" do
    assert Validator.validate_definition!([:integer], [min_items: 1], ["items"], :field) == :ok

    assert Validator.validate_definition!(
             %{count: {:integer, minimum: 0}, tags: {[:string], min_items: 1}},
             [],
             ["payload"],
             :field
           ) == :ok

    assert_raise ArgumentError,
                 ~r/invalid schema at items\.\[\]: options \[:optional\] are only valid on fields/,
                 fn ->
                   Validator.validate_definition!([{:string, optional: true}], [], ["items"], :field)
                 end

    assert_raise ArgumentError, ~r/invalid schema at payload: nested field name must be an atom/, fn ->
      Validator.validate_definition!(%{"count" => :integer}, [], ["payload"], :field)
    end
  end
end
