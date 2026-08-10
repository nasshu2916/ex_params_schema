defmodule ExParamsSchema.Schema.OptionsTest do
  use ExUnit.Case, async: true

  doctest ExParamsSchema.Schema.Options

  alias ExParamsSchema.Schema.Options

  test "既定値を補完し、strictを上書きする" do
    assert Options.normalize!([], "schema") == %Options{strict: false}
    assert Options.normalize!([strict: true], "schema") == %Options{strict: true}

    assert Options.normalize!([], "schema", %Options{strict: true}) == %Options{strict: true}
  end

  test "未知optionと不正なstrict値を拒否する" do
    assert_raise ArgumentError,
                 "schema options cannot contain unknown keys. Allowed keys: :strict",
                 fn ->
                   Options.normalize!([unknown: true], "schema")
                 end

    assert_raise ArgumentError, "schema :strict must be a boolean", fn ->
      Options.normalize!([strict: :yes], "schema")
    end
  end
end
