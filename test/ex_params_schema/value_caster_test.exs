defmodule ExParamsSchema.ValueCasterTest do
  use ExUnit.Case, async: true

  alias ExParamsSchema.Definition
  alias ExParamsSchema.ValueCaster

  defmodule RejectingType do
    @behaviour ExParamsSchema.Type

    @impl true
    def cast(_value, _options), do: {:error, :adapter_detail}

    @impl true
    def to_json(value, _options), do: value

    @impl true
    def json_schema(_options), do: %{"type" => "string"}
  end

  test "scalar と nullable を詳細結果へ変換する" do
    assert {:ok, 12} = ValueCaster.cast_detailed("12", :integer, [], :invalid_count)
    assert {:ok, nil} = ValueCaster.cast_detailed(nil, :integer, [nullable: true], :invalid_count)
    assert {:ok, nil} = ValueCaster.cast_detailed(nil, :null, [], :invalid_null)

    assert {:error, {[], :invalid_count}} =
             ValueCaster.cast_detailed(nil, :integer, [], :invalid_count)
  end

  test "custom type の失敗を呼び出し元の reason に正規化する" do
    assert {:error, {[], :invalid_token}} =
             ValueCaster.cast_detailed(
               "invalid",
               {:custom, RejectingType, []},
               [],
               :invalid_token
             )
  end

  test "strict object の未知キーを親フィールドの reason に正規化する" do
    fields = Definition.compile_fields!([{:count, :integer, []}])

    assert {:error, :invalid_payload} =
             ValueCaster.cast(%{"count" => "1", "extra" => true}, {:object, fields}, [strict: true], :invalid_payload)
  end

  test "strict objectの未知キーは詳細結果でadditional_propertiesと相対pathを保持する" do
    fields = Definition.compile_fields!([{:count, :integer, []}])

    assert {:error,
            %ExParamsSchema.ValidationError{
              path: ["extra"],
              keyword: :additional_properties,
              reason: :invalid_payload,
              details: %{key: "extra"}
            }} =
             ValueCaster.cast_detailed(
               %{"count" => "1", "extra" => true},
               {:object, fields},
               [strict: true],
               :invalid_payload
             )
  end

  test "ネストした optional と default を変換する" do
    fields =
      Definition.compile_fields!([
        {:count, :integer, default: "2"},
        {:label, :string, optional: true}
      ])

    assert {:ok, %{count: 2, label: nil}} =
             ValueCaster.cast(%{}, {:object, fields}, [], :invalid_payload)
  end

  test "cast_field は入力、default、optional な空値、必須欠損を区別する" do
    default = hd(Definition.compile_fields!([{:count, :integer, default: "2"}]))
    optional = hd(Definition.compile_fields!([{:label, :string, optional: true}]))
    required = hd(Definition.compile_fields!([{:name, :string, []}]))

    assert {:ok, :count, 2} = ValueCaster.cast_field(%{}, default)
    assert {:ok, :label, nil} = ValueCaster.cast_field(%{"label" => "  "}, optional)
    assert {:error, {["name"], {:invalid_param, :name}}} = ValueCaster.cast_field(%{}, required)
  end

  test "詳細変換結果はネストした object と array の相対パスを保持する" do
    fields =
      Definition.compile_fields!([
        {:entries, [%{count: {:integer, error: :invalid_count}}], []}
      ])

    assert {:error, {["entries", 0, "count"], :invalid_count}} =
             ValueCaster.cast_detailed(
               %{"entries" => [%{"count" => "invalid"}]},
               {:object, fields},
               [],
               :invalid_payload
             )
  end

  test "配列要素の変換エラーには添字を付与する" do
    assert {:error, {[1], :invalid_item}} =
             ValueCaster.cast_detailed(["1", "invalid"], {:array, :integer, []}, [], :invalid_item)
  end

  test "array と object の型不一致は指定された reason を返す" do
    fields = Definition.compile_fields!([{:count, :integer, []}])

    assert {:error, {[], :invalid_items}} =
             ValueCaster.cast_detailed(%{}, {:array, :integer, []}, [], :invalid_items)

    assert {:error, {[], :invalid_payload}} =
             ValueCaster.cast_detailed([], {:object, fields}, [], :invalid_payload)
  end

  test "互換 API は詳細なネスト path を公開せず reason だけを返す" do
    fields =
      Definition.compile_fields!([
        {:entries, [%{count: {:integer, error: :invalid_count}}], []}
      ])

    assert {:error, :invalid_count} =
             ValueCaster.cast(
               %{"entries" => [%{"count" => "invalid"}]},
               {:object, fields},
               [],
               :invalid_payload
             )
  end
end
