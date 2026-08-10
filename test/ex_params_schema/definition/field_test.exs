defmodule ExParamsSchema.Definition.FieldTest do
  use ExUnit.Case, async: true

  doctest ExParamsSchema.Definition.Field

  alias ExParamsSchema.Definition.Field

  describe "input_key/1 と error_reason/2" do
    test "source、フィールド固有の error、継承した error を優先する" do
      assert Field.input_key(field(:display_name, :string)) == "display_name"
      assert Field.input_key(field(:display_name, :string, source: :name)) == :name
      assert Field.input_key(:display_name, []) == "display_name"
      assert Field.input_key(:display_name, source: "displayName") == "displayName"
      assert Field.input_key(:display_name, source: :name) == :name

      assert Field.error_reason(field(:count, :integer, error: :invalid_count), :invalid_params) ==
               :invalid_count

      assert Field.error_reason(field(:count, :integer), :invalid_params) == :invalid_params
      assert Field.error_reason(field(:count, :integer)) == {:invalid_param, :count}
    end
  end

  describe "optional?/1" do
    test "optional option を返す" do
      assert Field.optional?(field(:label, :string, optional: true))
      refute Field.optional?(field(:label, :string))
    end
  end

  describe "fetch_value/2" do
    test "sourceの値を優先し、存在しない場合はatom keyへフォールバックする" do
      field = field(:count, :integer, source: "input-count")

      assert Field.fetch_value(%{"input-count" => "1", count: "2"}, field) == {:ok, "1"}
      assert Field.fetch_value(%{count: "2"}, field) == {:ok, "2"}
      assert Field.fetch_value(%{}, field) == :error
    end
  end

  describe "optional_empty?/2" do
    test "optionalな文字列だけ空白を未指定相当として扱う" do
      optional_string = field(:label, :string, optional: true)
      required_string = field(:label, :string)
      optional_integer = field(:count, :integer, optional: true)

      assert Field.optional_empty?(optional_string, " \t\n")
      refute Field.optional_empty?(required_string, " ")
      refute Field.optional_empty?(optional_integer, " ")
    end

    test "nil と空文字は optional の場合だけ未指定相当として扱う" do
      optional = field(:label, :string, optional: true)
      required = field(:label, :string)

      assert Field.optional_empty?(optional, nil)
      assert Field.optional_empty?(optional, "")
      refute Field.optional_empty?(required, nil)
      refute Field.optional_empty?(required, "")
      refute Field.optional_empty?(optional, 0)
    end
  end

  describe "missing_value/1" do
    test "default、optional、requiredの優先順を正規化する" do
      assert Field.missing_value(field(:count, :integer, default: "1", optional: true)) ==
               {:default, "1"}

      assert Field.missing_value(field(:label, :string, optional: true)) == :optional
      assert Field.missing_value(field(:count, :integer)) == :required
    end
  end

  describe "unknown_input_key/2" do
    test "sourceとatom keyを既知の入力として扱う" do
      fields = [field(:count, :integer, source: "input-count")]

      assert Field.unknown_input_key(%{"input-count" => "1", count: "2"}, fields) == nil
      assert Field.unknown_input_key(%{"unknown" => "1"}, fields) == "unknown"
    end

    test "入力が空の場合は未知のキーがない" do
      assert Field.unknown_input_key(%{}, [field(:count, :integer)]) == nil
    end
  end

  describe "omit_from_validation?/2" do
    test "optionalのnilだけを省略する" do
      assert Field.omit_from_validation?(field(:label, :string, optional: true), nil)
      refute Field.omit_from_validation?(field(:label, :string, nullable: true), nil)
      refute Field.omit_from_validation?(field(:label, :string, optional: true), "")
    end
  end

  defp field(name, type, options \\ []), do: %Field{name: name, type: type, options: options}
end
