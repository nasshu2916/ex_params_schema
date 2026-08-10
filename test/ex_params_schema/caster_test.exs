defmodule ExParamsSchema.CasterTest do
  use ExUnit.Case, async: true

  doctest ExParamsSchema.Caster

  alias ExParamsSchema.Caster

  @reason :invalid_value

  defmodule PrefixType do
    @behaviour ExParamsSchema.Type

    @impl true
    def cast("id:" <> value, _options), do: {:ok, value}
    def cast(_value, _options), do: {:error, :invalid_prefix}

    @impl true
    def to_json(value, _options), do: value

    @impl true
    def json_schema(_options), do: %{"type" => "string"}
  end

  test "整数へ変換する" do
    assert {:ok, 12} = Caster.cast("12", :integer, @reason)
    assert {:ok, -12} = Caster.cast(-12, :integer, @reason)
    assert {:error, @reason} = Caster.cast("12px", :integer, @reason)
    assert {:error, @reason} = Caster.cast(12.0, :integer, @reason)
  end

  test "数値文字列の指数表記、符号、空白を型ごとに区別する" do
    for value <- ["12", "+12", "-12"] do
      assert {:ok, _integer} = Caster.cast(value, :integer, @reason)
      assert {:ok, _float} = Caster.cast(value, :float, @reason)
      assert {:ok, _number} = Caster.cast(value, :number, @reason)
    end

    assert {:error, @reason} = Caster.cast("1e3", :integer, @reason)
    assert {:ok, 1_000.0} = Caster.cast("1e3", :float, @reason)
    assert {:ok, 1_000.0} = Caster.cast("1e3", :number, @reason)

    assert {:error, @reason} = Caster.cast("12.0", :integer, @reason)
    assert {:ok, 12.0} = Caster.cast("12.0", :float, @reason)
    assert {:ok, 12.0} = Caster.cast("12.0", :number, @reason)

    for value <- [" 12", "12 ", " 1e3 "] do
      assert {:error, @reason} = Caster.cast(value, :integer, @reason)
      assert {:error, @reason} = Caster.cast(value, :float, @reason)
      assert {:error, @reason} = Caster.cast(value, :number, @reason)
    end
  end

  test "浮動小数点数と数値へ変換する" do
    assert {:ok, 12.5} = Caster.cast(12.5, :float, @reason)
    assert {:ok, 12.0} = Caster.cast("12.0", :float, @reason)
    assert {:ok, 12.0} = Caster.cast(12, :float, @reason)
    assert {:ok, 12.5} = Caster.cast(12.5, :number, @reason)
    assert {:ok, 12} = Caster.cast("12", :number, @reason)
    assert {:ok, 12.5} = Caster.cast("12.5", :number, @reason)
    assert {:error, @reason} = Caster.cast("12.5px", :number, @reason)
  end

  test "LiveView から届く真偽値の表現を変換する" do
    for value <- [true, "true", "on", "1", 1] do
      assert {:ok, true} = Caster.cast(value, :boolean, @reason)
    end

    for value <- [false, "false", "off", "0", 0] do
      assert {:ok, false} = Caster.cast(value, :boolean, @reason)
    end

    for value <- ["yes", "TRUE", "false ", "", -1, 2, nil] do
      assert {:error, @reason} = Caster.cast(value, :boolean, @reason)
    end
  end

  test "文字列を整形する" do
    assert {:ok, "Front"} = Caster.cast("  Front  ", :string, @reason)
    assert {:error, @reason} = Caster.cast(10, :string, @reason)
  end

  test "ISO 8601の日付と日時をドメイン型へ変換する" do
    assert {:ok, ~D[2026-07-22]} = Caster.cast("2026-07-22", :date, @reason)
    assert {:ok, ~D[2026-07-22]} = Caster.cast(~D[2026-07-22], :date, @reason)
    assert {:error, @reason} = Caster.cast("2026-02-30", :date, @reason)

    assert {:ok, ~U[2026-07-22 03:04:05Z]} =
             Caster.cast("2026-07-22T12:04:05+09:00", :datetime, @reason)

    assert {:ok, ~U[2026-07-22 03:04:05Z]} =
             Caster.cast(~U[2026-07-22 03:04:05Z], :datetime, @reason)

    assert {:error, @reason} = Caster.cast("2026-07-22T03:04:05", :datetime, @reason)
  end

  test "enum の文字列表現を定義値へ変換する" do
    type = {:enum, [:merge, :replace]}

    assert {:ok, :merge} = Caster.cast("merge", type, @reason)
    assert {:ok, :replace} = Caster.cast(:replace, type, @reason)
    assert {:error, @reason} = Caster.cast("remove", type, @reason)
  end

  test "custom type の変換結果と失敗理由を委譲する" do
    type = {:custom, PrefixType, [prefix: "id:"]}

    assert {:ok, "123"} = Caster.cast("id:123", type, @reason)
    assert {:error, @reason} = Caster.cast("123", type, @reason)
  end

  test "any と null を変換する" do
    assert {:ok, %{value: 1}} = Caster.cast(%{value: 1}, :any, @reason)
    assert {:ok, nil} = Caster.cast(nil, :null, @reason)
    assert {:error, @reason} = Caster.cast("null", :null, @reason)
  end
end
