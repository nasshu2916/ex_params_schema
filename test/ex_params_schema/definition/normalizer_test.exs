defmodule ExParamsSchema.Definition.NormalizerTest do
  use ExUnit.Case, async: true

  alias ExParamsSchema.Definition.Normalizer

  defmodule CustomType do
    @behaviour ExParamsSchema.Type

    @impl true
    def cast(value, _options), do: {:ok, value}

    @impl true
    def to_json(value, _options), do: value

    @impl true
    def json_schema(_options), do: %{}
  end

  test "短縮定義を正規化する" do
    assert Normalizer.normalize!({:enum, [:draft, :published]}) == {{:enum, [:draft, :published]}, []}
    assert Normalizer.normalize!({CustomType, enabled: true}) == {{:custom, CustomType, [enabled: true]}, []}
  end

  test "プリミティブ型とリスト型を正規化する" do
    assert Normalizer.normalize!(:integer) == {:integer, []}
    assert Normalizer.normalize!({:string, min_length: 1}) == {:string, [min_length: 1]}
    assert Normalizer.normalize!([:integer]) == {[:integer], []}
    assert Normalizer.normalize!({[:string], min_items: 1}) == {[:string], [min_items: 1]}
  end

  test "map 形式のスキーマをフィールド定義へ変換する" do
    assert Normalizer.fields_from_map!(%{count: {:integer, minimum: 1}}) == [{:count, :integer, [minimum: 1]}]
  end

  test "標準型とカスタム型の不正な option を拒否する" do
    assert_raise ArgumentError, ~r/unknown schema options: \[:minimun\]/, fn ->
      Normalizer.normalize!({:integer, minimun: 1})
    end

    assert_raise ArgumentError, ~r/must not contain duplicate keys/, fn ->
      Normalizer.normalize!({CustomType, enabled: true, enabled: false})
    end
  end
end
