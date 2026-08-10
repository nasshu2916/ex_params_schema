defmodule ExParamsSchema.Schema.ErrorPathTest do
  use ExUnit.Case, async: true

  alias ExParamsSchema.Schema.ErrorPath

  test "最も具体的なエラー定義へJSON Pointerを対応付ける" do
    definitions = [
      {["payload"], :invalid_payload, 0},
      {["payload", "entries"], :invalid_entries, 1},
      {["payload", "entries", :index], :invalid_entry, 2}
    ]

    assert ErrorPath.resolve(definitions, "#/payload/entries/3/minimum") ==
             {2, :invalid_entry, ["payload", "entries", 3, "minimum"]}
  end

  test "対応するエラー定義がない、または不正なJSON Pointerではnilを返す" do
    definitions = [{["count"], :invalid_count, 0}]

    assert ErrorPath.resolve(definitions, "#/unknown/minimum") == nil
    assert ErrorPath.resolve(definitions, "invalid") == nil
  end
end
