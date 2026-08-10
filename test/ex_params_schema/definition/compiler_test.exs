defmodule ExParamsSchema.Definition.CompilerTest do
  use ExUnit.Case, async: true

  alias ExParamsSchema.Definition.{Compiler, Field}

  test "パーサー向けの中間表現へコンパイルする" do
    fields = [
      {:count, :integer, []},
      {:label, :string, [optional: true]},
      {:entries, [%{count: {:integer, minimum: 1}}], []}
    ]

    assert Compiler.compile_fields!(fields) == [
             %Field{name: :count, type: :integer, options: []},
             %Field{name: :label, type: :string, options: [optional: true]},
             %Field{
               name: :entries,
               type:
                 {:array,
                  {:object,
                   [
                     %Field{name: :count, type: :integer, options: [minimum: 1]}
                   ]}, []}
             }
           ]
  end

  test "map形式の外部定義を検証済みフィールドへコンパイルする" do
    assert [%Field{name: :payload, type: {:object, [%Field{name: :count, type: :integer}]}}] =
             ExParamsSchema.Definition.compile!(%{payload: %{count: :integer}})
  end

  test "map形式の外部定義でも正規化と検証を経由する" do
    assert [%Field{name: :count, type: :integer, options: [source: "input-count", minimum: 1]}] =
             ExParamsSchema.Definition.compile!(%{
               count: {:integer, source: "input-count", minimum: 1}
             })

    assert_raise ArgumentError, ~r/unknown schema options: \[:minimun\]/, fn ->
      ExParamsSchema.Definition.compile!(%{count: {:integer, minimun: 1}})
    end

    assert_raise ArgumentError, ~r/invalid schema at payload\.count: invalid minimum/, fn ->
      ExParamsSchema.Definition.compile!(%{payload: %{count: {:integer, minimum: "1"}}})
    end
  end

  test "公開APIからフィールド定義を正規化して重複を検証する" do
    assert [{:count, :integer, [source: "input-count"]}] =
             ExParamsSchema.Definition.normalize_fields!([{:count, :integer, source: "input-count"}])

    assert_raise ArgumentError, ~r/input key "count" is used by both fields/, fn ->
      ExParamsSchema.Definition.normalize_fields!([
        {:first, :integer, source: "count"},
        {:second, :integer, source: "count"}
      ])
    end
  end
end
