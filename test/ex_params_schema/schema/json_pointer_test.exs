defmodule ExParamsSchema.Schema.JsonPointerTest do
  use ExUnit.Case, async: true

  alias ExParamsSchema.Schema

  describe "decode/1" do
    test "JSON Pointerをデコードする" do
      assert Schema.JsonPointer.decode("#") == {:ok, []}
      assert Schema.JsonPointer.decode("#/a~1b~0c/0") == {:ok, ["a/b~c", "0"]}
      assert Schema.JsonPointer.decode("invalid") == :error
    end

    test "空セグメントとRFC 6901のエスケープを保持する" do
      assert Schema.JsonPointer.decode("#/") == {:ok, [""]}
      assert Schema.JsonPointer.decode("#/a//b") == {:ok, ["a", "", "b"]}
      assert Schema.JsonPointer.decode("#/~01") == {:ok, ["~1"]}
    end
  end

  describe "parse/1" do
    test "root、添字、不正なpointerを解決済みパスへ変換する" do
      assert Schema.JsonPointer.parse("#") == []
      assert Schema.JsonPointer.parse("#/entries/0/value") == ["entries", 0, "value"]
      assert Schema.JsonPointer.parse("#/a~1b~0c") == ["a/b~c"]
      assert Schema.JsonPointer.parse("invalid") == []
    end
  end

  describe "match/2" do
    test "パターンの先頭一致を解決済みパスに変換する" do
      assert Schema.JsonPointer.match(["entries", :index], ["entries", "3", "value"]) ==
               {:ok, ["entries", 3, "value"]}
    end

    test "文字列セグメントと添字を区別する" do
      assert Schema.JsonPointer.match(["0"], ["0"]) == {:ok, ["0"]}
      assert Schema.JsonPointer.match([:index], ["-1"]) == :error
      assert Schema.JsonPointer.match([:index], ["01"]) == :error
      assert Schema.JsonPointer.match([:index], ["+1"]) == :error
      assert Schema.JsonPointer.match(["entry"], ["entries"]) == :error
    end

    test "エスケープされていないスラッシュを含む既存形式のPointerにも対応する" do
      assert Schema.JsonPointer.match(["a/b~c"], ["a", "b~c", "minimum"]) ==
               {:ok, ["a/b~c", "minimum"]}
    end
  end

  test "未解決のパスでは数値の添字を整数に変換する" do
    assert Schema.JsonPointer.resolve_segments(["entries", "0", "value"]) == ["entries", 0, "value"]
    assert Schema.JsonPointer.resolve_segments(["entries", "10", "value"]) == ["entries", 10, "value"]
    assert Schema.JsonPointer.resolve_segments(["01", "+1"]) == ["01", "+1"]
  end

  test "JSON Pointerのセグメントをエスケープする" do
    assert Schema.JsonPointer.escape_segment("plain") == "plain"
    assert Schema.JsonPointer.escape_segment("a/b~c") == "a~1b~0c"
  end
end
