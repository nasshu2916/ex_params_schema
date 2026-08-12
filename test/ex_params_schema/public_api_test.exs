defmodule ExParamsSchema.PublicApiTest do
  use ExUnit.Case, async: true

  doctest ExParamsSchema.Definition
  doctest ExParamsSchema.Schema.JsonSchema
  doctest ExParamsSchema.Schema.Projector
  doctest ExParamsSchema.Schema.Validator
  doctest ExParamsSchema.ValidationError
  doctest ExParamsSchema.ValueCaster

  test "useオプションのstrictはbooleanだけを許可する" do
    assert_raise ArgumentError, "use ExParamsSchema :strict must be a boolean", fn ->
      Code.compile_string("""
      defmodule InvalidUseOptionsParams do
        use ExParamsSchema, strict: :yes
      end
      """)
    end
  end

  test "useの未知オプションを拒否する" do
    assert_raise ArgumentError,
                 "use ExParamsSchema options cannot contain unknown keys. Allowed keys: :strict",
                 fn ->
                   Code.compile_string("""
                   defmodule InvalidUseUnknownOptionParams do
                     use ExParamsSchema, unknown: true
                   end
                   """)
                 end
  end

  test "map以外の入力を公開parse APIで拒否する" do
    schema = ExParamsSchema.compile!(%{count: :integer})

    assert {:error, :invalid_params} = ExParamsSchema.parse([], schema)

    assert {:error,
            [
              %ExParamsSchema.ValidationError{
                path: [],
                keyword: :cast,
                reason: :invalid_params
              }
            ]} = ExParamsSchema.parse_detailed([], schema)
  end

  test "詳細エラーをフォーム表示用にパスごとでまとめる" do
    errors = [
      %ExParamsSchema.ValidationError{path: ["email"], keyword: :format, reason: :invalid_email},
      %ExParamsSchema.ValidationError{path: ["email"], keyword: :min_length, reason: :invalid_email},
      %ExParamsSchema.ValidationError{path: ["profile", "name"], keyword: :cast, reason: :invalid_name}
    ]

    assert ExParamsSchema.ValidationError.to_form_errors(errors) == %{
             ["email"] => [:invalid_email, :invalid_email],
             ["profile", "name"] => [:invalid_name]
           }
  end

  test "フォーム表示用エラーは配列の添字を含むパスを保持する" do
    errors = [
      %ExParamsSchema.ValidationError{
        path: ["entries", 0, "name"],
        keyword: :min_length,
        reason: :invalid_name
      },
      %ExParamsSchema.ValidationError{
        path: ["entries", 1, "name"],
        keyword: :cast,
        reason: :invalid_name
      }
    ]

    assert ExParamsSchema.ValidationError.to_form_errors(errors) == %{
             ["entries", 0, "name"] => [:invalid_name],
             ["entries", 1, "name"] => [:invalid_name]
           }
  end

  test "compileとjson_schemaの未知オプションを拒否する" do
    assert_raise ArgumentError,
                 "compile! options cannot contain unknown keys. Allowed keys: :strict",
                 fn ->
                   ExParamsSchema.compile!(%{count: :integer}, unknown: true)
                 end

    assert_raise ArgumentError,
                 "json_schema options cannot contain unknown keys. Allowed keys: :strict",
                 fn ->
                   ExParamsSchema.json_schema(%{count: :integer}, unknown: true)
                 end
  end
end
