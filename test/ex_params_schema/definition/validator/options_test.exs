defmodule ExParamsSchema.Definition.Validator.OptionsTest do
  use ExUnit.Case, async: true

  alias ExParamsSchema.Definition.Validator.Options

  test "scalar 型の membership 値を検証する" do
    assert Options.validate!([enum: [nil]], :null, ["empty"], :field) == :ok
    assert Options.validate!([enum: [true, false]], :boolean, ["enabled"], :field) == :ok
    assert Options.validate!([enum: [1, 1.5]], :number, ["ratio"], :field) == :ok

    assert_raise ArgumentError, ~r/invalid enum: values must be compatible with :integer/, fn ->
      Options.validate!([enum: [1, "2"]], :integer, ["count"], :field)
    end
  end

  test "型に適用できない制約と不正な値を拒否する" do
    assert_raise ArgumentError, ~r/cannot be used with :string/, fn ->
      Options.validate!([minimum: 1], :string, ["label"], :field)
    end

    assert_raise ArgumentError, ~r/invalid unique_items/, fn ->
      Options.validate!([unique_items: :yes], :array, ["items"], :field)
    end

    assert_raise ArgumentError, ~r/minimum must be less than or equal to maximum/, fn ->
      Options.validate!([minimum: 2, maximum: 1], :integer, ["count"], :field)
    end
  end

  test "入れ子では field 専用 option を拒否する" do
    assert_raise ArgumentError, ~r/options \[:optional\] are only valid on fields/, fn ->
      Options.validate!([optional: true], :integer, ["items", "[]"], :item)
    end

    assert_raise ArgumentError, ~r/options \[:format\] cannot be used with :date/, fn ->
      Options.validate!([format: "date"], :date, ["published_on"], :field)
    end
  end

  test "membership の有限性と nullable を検証する" do
    assert Options.validate!([in: 1..3], :integer, ["count"], :field) == :ok

    assert Options.validate!([enum: [nil, "draft"], nullable: true], :string, ["label"], :field) ==
             :ok

    assert Options.validate!([enum: [1, "value", %{key: :value}]], :any, ["value"], :field) == :ok

    assert_raise ArgumentError, ~r/invalid in/, fn ->
      Options.validate!([in: Stream.iterate(1, &(&1 + 1))], :integer, ["count"], :field)
    end

    assert_raise ArgumentError, ~r/invalid enum: values must be compatible with :string/, fn ->
      Options.validate!([enum: [nil, "draft"]], :string, ["label"], :field)
    end
  end

  test "制約ごとの型と値を検証する" do
    assert_raise ArgumentError, ~r/options \[:pattern\] cannot be used with :integer/, fn ->
      Options.validate!([pattern: "^1$"], :integer, ["count"], :field)
    end

    assert_raise ArgumentError, ~r/invalid format/, fn ->
      Options.validate!([format: :email], :string, ["label"], :field)
    end

    assert_raise ArgumentError, ~r/invalid min_length/, fn ->
      Options.validate!([min_length: -1], :string, ["label"], :field)
    end

    assert_raise ArgumentError, ~r/options \[:strict\] cannot be used with :string/, fn ->
      Options.validate!([strict: true], :string, ["label"], :field)
    end
  end

  test "custom type では membership だけを拒否する" do
    assert Options.validate!([minimum: 1], :custom, ["price"], :field) == :ok

    assert_raise ArgumentError, ~r/options \[:enum\] cannot be used with :custom/, fn ->
      Options.validate!([enum: [:standard]], :custom, ["price"], :field)
    end
  end
end
