defmodule ExParamsSchema.Definition.OptionsTest do
  use ExUnit.Case, async: true

  alias ExParamsSchema.Definition.Options

  test "既知の keyword だけを許可する" do
    assert Options.validate!(minimum: 1) == :ok

    assert_raise ArgumentError, ~r/unknown schema options: \[:minimun\]/, fn ->
      Options.validate!(minimun: 1)
    end
  end

  test "重複したキーを許可しない" do
    assert_raise ArgumentError, ~r/must not contain duplicate keys/, fn ->
      Options.validate!(minimum: 1, minimum: 2)
    end
  end

  test "option は keyword list でなければならない" do
    assert_raise ArgumentError, ~r/must be a keyword list/, fn ->
      Options.validate!([:minimum])
    end

    assert_raise ArgumentError, ~r/must be a keyword list/, fn ->
      Options.validate_custom!(%{minimum_cents: 1})
    end
  end

  test "custom type の option は keyword 形式のみを検証する" do
    assert Options.validate_custom!(minimum_cents: 1) == :ok

    assert_raise ArgumentError, ~r/must not contain duplicate keys/, fn ->
      Options.validate_custom!(enabled: true, enabled: false)
    end
  end

  test "custom type の option は未知のキーを許可する" do
    assert Options.validate_custom!(minimum_cents: 1, currency: :jpy) == :ok
  end

  test "宣言した規則から既知キー、field 専用キー、JSON Schema keyword を導出する" do
    assert :minimum in Options.known()
    assert Options.field_only() == [:default, :optional, :source]

    assert Options.json_schema_options() == [
             minimum: "minimum",
             maximum: "maximum",
             min_length: "minLength",
             max_length: "maxLength",
             pattern: "pattern",
             format: "format",
             min_items: "minItems",
             max_items: "maxItems",
             unique_items: "uniqueItems"
           ]
  end

  test "宣言した規則から option の値と型への適用可否を検証する" do
    assert Options.valid_value?(:minimum, 1)
    refute Options.valid_value?(:minimum, "1")
    assert Options.allowed_for_type?(:minimum, :integer)
    refute Options.allowed_for_type?(:minimum, :string)
    assert Options.allowed_for_type?(:minimum, :custom)
    refute Options.allowed_for_type?(:enum, :custom)
  end

  test "未知の規則は値と型の検証で拒否する" do
    refute Options.valid_value?(:unknown, :value)
    refute Options.allowed_for_type?(:unknown, :string)
  end
end
