defmodule ExParamsSchemaTest do
  use ExUnit.Case, async: true

  doctest ExParamsSchema

  defmodule ExampleParams do
    use ExParamsSchema

    field :fixture_id, :integer, source: "fixture-id", in: 1..9999, error: :invalid_fixture
    field :level, :integer, in: 0..255, error: :invalid_level
    field :mode, {:enum, [:merge, :replace]}, error: :invalid_mode
    field :label, :string, optional: true
    field :enabled, :boolean, default: false
  end

  defmodule DslParams do
    use ExParamsSchema

    defschema do
      field :fixture_id, :integer,
        source: "fixture-id",
        minimum: 1,
        maximum: 9999,
        error: :invalid_fixture

      field :level, :integer, minimum: 0, maximum: 255, error: :invalid_level
      field :mode, :string, enum: ["merge", "replace"], error: :invalid_mode
      field :label, :string, optional: true, min_length: 2, max_length: 10, error: :invalid_label
      field :ratio, :number, nullable: true, error: :invalid_ratio
      field :empty, :null

      field :channels, [{:integer, minimum: 1, maximum: 512}],
        min_items: 1,
        max_items: 3,
        error: :invalid_channels

      field :point, %{x: :integer, y: :integer}, optional: true, error: :invalid_point
    end
  end

  defmodule StrictParams do
    use ExParamsSchema

    defschema strict: true do
      field :id, :integer, source: "input-id"
      field :profile, %{name: :string}, strict: true, error: :invalid_profile
    end
  end

  defmodule InheritedStrictParams do
    use ExParamsSchema, strict: true

    defschema do
      field :id, :integer
    end
  end

  defmodule OverriddenStrictParams do
    use ExParamsSchema, strict: true

    defschema strict: false do
      field :id, :integer
    end
  end

  defmodule DefaultParams do
    use ExParamsSchema

    defschema do
      field :count, :integer, default: "2", minimum: 1, maximum: 3, error: :invalid_count
    end
  end

  defmodule TemporalParams do
    use ExParamsSchema

    defschema do
      field :published_on, :date, default: "2026-07-22"
      field :published_at, :datetime
    end
  end

  defmodule PriceType do
    @behaviour ExParamsSchema.Type

    @type t :: %{cents: pos_integer()}

    @impl true
    def cast(value, options) when is_binary(value) do
      with {cents, ""} <- Integer.parse(value),
           true <- cents >= Keyword.fetch!(options, :minimum_cents) do
        {:ok, %{cents: cents}}
      else
        _other -> {:error, :invalid_price}
      end
    end

    def cast(%{cents: cents} = value, options) when is_integer(cents) do
      if cents >= Keyword.fetch!(options, :minimum_cents),
        do: {:ok, value},
        else: {:error, :invalid_price}
    end

    def cast(_value, _options), do: {:error, :invalid_price}

    @impl true
    def to_json(%{cents: cents}, _options), do: cents

    @impl true
    def json_schema(_options), do: %{"type" => "integer"}

    @impl true
    def validate(%{cents: cents}, _options) when rem(cents, 5) == 0, do: :ok
    def validate(_value, _options), do: {:error, :invalid_increment}

    @impl true
    def validate_options(options) do
      if Keyword.keyword?(options) and is_integer(options[:minimum_cents]) do
        :ok
      else
        {:error, "minimum_cents must be an integer"}
      end
    end
  end

  defmodule CustomTypeParams do
    use ExParamsSchema

    field :price, {PriceType, minimum_cents: 100}, minimum: 100, error: :invalid_price
  end

  defmodule SlugType do
    @behaviour ExParamsSchema.Type

    @type t :: String.t()

    @impl true
    def cast(value, _options) when is_binary(value) do
      slug = value |> String.trim() |> String.downcase()
      if slug == "", do: {:error, :empty_slug}, else: {:ok, slug}
    end

    def cast(_value, _options), do: {:error, :invalid_slug}

    @impl true
    def to_json(value, _options), do: value

    @impl true
    def json_schema(_options), do: %{"type" => "string"}
  end

  defmodule PrimitiveCustomTypeParams do
    use ExParamsSchema

    field :slug, {SlugType, []}, min_length: 3, error: :invalid_slug
  end

  defmodule CustomTypeDslParams do
    use ExParamsSchema

    defschema do
      field :price, {PriceType, minimum_cents: 100}, minimum: 100, error: :invalid_price
    end
  end

  defmodule OptionalDefaultParams do
    use ExParamsSchema

    defschema do
      field :label, :string, optional: true, default: "fallback"
    end
  end

  defmodule NestedBoundaryParams do
    use ExParamsSchema

    defschema do
      field :profile,
            %{
              display_name: {:string, optional: true, default: "Guest"},
              retries: {:integer, default: "2"},
              note: {:string, nullable: true}
            },
            error: :invalid_profile

      field :entries,
            [
              %{
                title: {:string, optional: true, default: "untitled"},
                rank: {:integer, nullable: true}
              }
            ],
            optional: true,
            error: :invalid_entries

      field :status, :string, source: "input-status", error: :invalid_status
    end
  end

  defmodule ValidationBoundaryParams do
    use ExParamsSchema

    defschema do
      field :first, :integer, minimum: 1, error: :invalid_first

      field :payload, %{count: {:integer, minimum: 1, error: :invalid_count}}, error: :invalid_payload

      field :entries, [%{value: {:integer, minimum: 1, error: :invalid_entry_value}}], error: :invalid_entries
    end
  end

  defmodule PresenceBoundaryParams do
    use ExParamsSchema

    defschema do
      field :scalar_default, :integer, default: "2"
      field :scalar_optional, :string, optional: true, default: "fallback"
      field :scalar_nullable, :string, nullable: true

      field :profile,
            %{
              default_value: {:integer, default: "3"},
              optional_value: {:string, optional: true, default: "profile fallback"},
              nullable_value: {:string, nullable: true}
            },
            optional: true

      field :entries,
            [
              %{
                default_value: {:integer, default: "4"},
                optional_value: {:string, optional: true, default: "entry fallback"},
                nullable_value: {:string, nullable: true}
              }
            ],
            optional: true
    end
  end

  defmodule SourceBoundaryParams do
    use ExParamsSchema

    defschema do
      field :atom_source, :integer, source: :input_count, error: :invalid_atom_source
      field :string_source, :integer, source: "input/count~value", error: :invalid_string_source
    end
  end

  test "文字列パラメーターを型付き構造体へ変換する" do
    assert {:ok,
            %ExampleParams{
              fixture_id: 12,
              level: 128,
              mode: :merge,
              label: "Front",
              enabled: true
            }} =
             ExampleParams.parse(%{
               "fixture-id" => "12",
               "level" => "128",
               "mode" => "merge",
               "label" => "  Front  ",
               "enabled" => "on"
             })
  end

  test "省略可能な値、デフォルト値、範囲エラーを扱う" do
    assert {:ok, %ExampleParams{label: nil, enabled: false}} =
             ExampleParams.parse(%{"fixture-id" => "1", "level" => "0", "mode" => "replace"})

    assert {:error, :invalid_level} =
             ExampleParams.parse(%{"fixture-id" => "1", "level" => "256", "mode" => "merge"})
  end

  test "独自 DSL の定義で型変換と制約検証を行う" do
    assert {:ok,
            %DslParams{
              fixture_id: 12,
              level: 128,
              mode: "merge",
              label: "Front",
              ratio: nil,
              empty: nil,
              channels: [1, 512],
              point: %{x: 10, y: 20}
            }} =
             DslParams.parse(%{
               "fixture-id" => "12",
               "level" => "128",
               "mode" => "merge",
               "label" => " Front ",
               "ratio" => nil,
               "empty" => nil,
               "channels" => ["1", "512"],
               "point" => %{"x" => "10", "y" => 20}
             })

    assert {:error, :invalid_fixture} = valid_simple_schema_params(%{"fixture-id" => "0"})
    assert {:error, :invalid_level} = valid_simple_schema_params(%{"level" => "256"})
    assert {:error, :invalid_mode} = valid_simple_schema_params(%{"mode" => "remove"})
    assert {:error, :invalid_label} = valid_simple_schema_params(%{"label" => "x"})
    assert {:error, :invalid_label} = valid_simple_schema_params(%{"label" => "too long label"})
    assert {:error, :invalid_channels} = valid_simple_schema_params(%{"channels" => []})

    assert {:error, :invalid_channels} =
             valid_simple_schema_params(%{"channels" => ["1", "2", "3", "4"]})
  end

  test "デフォルト値を型変換してから制約検証する" do
    assert {:ok, %DefaultParams{count: 2}} = DefaultParams.parse(%{})
    assert %DefaultParams{count: 2} = %DefaultParams{}
  end

  test "日付・日時をドメイン型として変換し、日時はUTCへ正規化する" do
    assert {:ok,
            %TemporalParams{
              published_on: ~D[2026-07-22],
              published_at: ~U[2026-07-22 03:04:05Z]
            }} =
             TemporalParams.parse(%{"published_at" => "2026-07-22T12:04:05+09:00"})

    assert %TemporalParams{published_on: ~D[2026-07-22]} = %TemporalParams{}

    assert {:error, {:invalid_param, :published_at}} =
             TemporalParams.parse(%{"published_at" => "invalid"})
  end

  test "{Module, opts}で独自型を変換・検証し、JSON Schema制約へ射影する" do
    assert {:ok, %CustomTypeParams{price: %{cents: 105}}} =
             CustomTypeParams.parse(%{"price" => "105"})

    assert {:ok, %CustomTypeDslParams{price: %{cents: 105}}} =
             CustomTypeDslParams.parse(%{"price" => "105"})

    assert {:error, :invalid_price} = CustomTypeParams.parse(%{"price" => "99"})
    assert {:error, :invalid_price} = CustomTypeParams.parse(%{"price" => "101"})
  end

  test "custom typeのt/0にプリミティブ型を指定できる" do
    assert {:ok, %PrimitiveCustomTypeParams{slug: "front"}} =
             PrimitiveCustomTypeParams.parse(%{"slug" => " Front "})

    assert {:error, :invalid_slug} = PrimitiveCustomTypeParams.parse(%{"slug" => "ab"})
  end

  test "map形式のフィールド定義からJSON Schema Draft 7を生成できる" do
    assert ExParamsSchema.json_schema(%{count: {:integer, minimum: 1}}) == %{
             "$schema" => "http://json-schema.org/draft-07/schema#",
             "type" => "object",
             "properties" => %{
               "count" => %{"type" => "integer", "minimum" => 1}
             },
             "required" => ["count"]
           }
  end

  test "生成したjson_schemaは宣言したスキーマを返す" do
    schema = ExampleParams.json_schema()

    assert schema["$schema"] == "http://json-schema.org/draft-07/schema#"
    assert schema["type"] == "object"
    assert schema["required"] == ["fixture_id", "level", "mode", "enabled"]
    assert [1, 2 | _] = schema["properties"]["fixture_id"]["enum"]
    assert List.last(schema["properties"]["fixture_id"]["enum"]) == 9999
    assert schema["properties"]["mode"] == %{"type" => "string", "enum" => ["merge", "replace"]}
    assert StrictParams.json_schema()["additionalProperties"] == false
  end

  test "field/3とdefschemaブロックを混在させた重複フィールド名を拒否する" do
    assert_raise ArgumentError, ~r/schema field name :count is declared more than once/, fn ->
      Code.compile_string("""
      defmodule DuplicateFieldNameParams do
        use ExParamsSchema

        field :count, :integer
        defschema do
          field :count, :string
        end
      end
      """)
    end
  end

  test "未知の入力を無視し、sourceとatom keyが競合した場合はsourceを優先する" do
    params = %{
      "fixture-id" => "1",
      :fixture_id => "2",
      "level" => "128",
      "mode" => "merge",
      "unknown" => "ignored"
    }

    assert {:ok, %ExampleParams{fixture_id: 1}} = ExampleParams.parse(params)
  end

  test "strict modeでは未知の入力を拒否し、入れ子のmapでは親フィールドのerrorを返す" do
    assert {:ok, %StrictParams{id: 1, profile: %{name: "Ada"}}} =
             StrictParams.parse(%{:id => "1", "profile" => %{:name => "Ada"}})

    assert {:error, {:unknown_param, "unknown"}} =
             StrictParams.parse(%{
               "input-id" => "1",
               "profile" => %{"name" => "Ada"},
               "unknown" => "value"
             })

    assert {:error, :invalid_profile} =
             StrictParams.parse(%{
               "input-id" => "1",
               "profile" => %{"name" => "Ada", "unknown" => "value"}
             })
  end

  test "defschemaはuseのstrictを継承し、明示したoptionで上書きできる" do
    params = %{"id" => "1", "unknown" => "value"}

    assert {:error, {:unknown_param, "unknown"}} = InheritedStrictParams.parse(params)
    assert {:ok, %OverriddenStrictParams{id: 1}} = OverriddenStrictParams.parse(params)
  end

  test "optionalな文字列の空白入力はnilとし、未指定の場合だけdefaultを使う" do
    assert {:ok, %OptionalDefaultParams{label: "fallback"}} = OptionalDefaultParams.parse(%{})

    assert {:ok, %OptionalDefaultParams{label: nil}} =
             OptionalDefaultParams.parse(%{"label" => ""})

    assert {:ok, %OptionalDefaultParams{label: nil}} =
             OptionalDefaultParams.parse(%{"label" => " \t\n "})
  end

  test "ネストしたmapとlistでoptional、nullable、defaultを組み合わせる" do
    params = %{
      "profile" => %{"display_name" => " ", "note" => nil},
      "entries" => [%{"rank" => nil}, %{"title" => " Draft ", "rank" => "3"}],
      "input-status" => "primary",
      :status => "fallback",
      "unknown" => "ignored"
    }

    assert {:ok,
            %NestedBoundaryParams{
              profile: %{display_name: nil, retries: 2, note: nil},
              entries: [%{title: "untitled", rank: nil}, %{title: "Draft", rank: 3}],
              status: "primary"
            }} = NestedBoundaryParams.parse(params)

    assert {:ok, %NestedBoundaryParams{entries: nil}} =
             NestedBoundaryParams.parse(%{
               "profile" => %{"note" => "memo"},
               "input-status" => "primary"
             })
  end

  test "scalar、nested object、list itemごとに未指定、空文字、nil、defaultを区別する" do
    assert {:ok,
            %PresenceBoundaryParams{
              scalar_default: 2,
              scalar_optional: "fallback",
              profile: nil,
              entries: nil
            }} = PresenceBoundaryParams.parse(%{"scalar_nullable" => nil})

    assert {:ok,
            %PresenceBoundaryParams{
              scalar_optional: nil,
              profile: %{default_value: 3, optional_value: nil, nullable_value: nil},
              entries: [%{default_value: 4, optional_value: nil, nullable_value: nil}]
            }} =
             PresenceBoundaryParams.parse(%{
               "scalar_optional" => " ",
               "scalar_nullable" => nil,
               "profile" => %{"optional_value" => "", "nullable_value" => nil},
               "entries" => [%{"optional_value" => " ", "nullable_value" => nil}]
             })

    assert {:error, {:invalid_param, :scalar_nullable}} = PresenceBoundaryParams.parse(%{})

    assert {:error, {:invalid_param, :profile}} =
             PresenceBoundaryParams.parse(%{"scalar_nullable" => nil, "profile" => %{}})

    assert {:error, {:invalid_param, :entries}} =
             PresenceBoundaryParams.parse(%{"scalar_nullable" => nil, "entries" => [%{}]})
  end

  test "sourceのatomとstringを入力キーとして優先する" do
    params = %{
      :input_count => "2",
      :atom_source => "3",
      "input/count~value" => "4",
      :string_source => "5"
    }

    assert {:ok, %SourceBoundaryParams{atom_source: 2, string_source: 4}} =
             SourceBoundaryParams.parse(params)
  end

  test "複数のバリデーションエラーでは宣言順を保ち、最も近いerrorを選ぶ" do
    assert {:error, :invalid_count} =
             ValidationBoundaryParams.parse(%{
               "first" => "1",
               "payload" => %{"count" => "0"},
               "entries" => [%{"value" => "1"}]
             })

    assert {:error, :invalid_first} =
             ValidationBoundaryParams.parse(%{
               "first" => "0",
               "payload" => %{"count" => "0"},
               "entries" => [%{"value" => "0"}]
             })
  end

  test "生成したparse_detailedは構造体と詳細エラーを返す" do
    assert {:ok,
            %ValidationBoundaryParams{
              first: 1,
              payload: %{count: 1},
              entries: [%{value: 1}]
            }} =
             ValidationBoundaryParams.parse_detailed(%{
               "first" => "1",
               "payload" => %{"count" => "1"},
               "entries" => [%{"value" => "1"}]
             })

    assert {:error,
            [
              %ExParamsSchema.ValidationError{
                path: ["payload", "count"],
                keyword: :minimum,
                reason: :invalid_count
              }
            ]} =
             ValidationBoundaryParams.parse_detailed(%{
               "first" => "1",
               "payload" => %{"count" => "0"},
               "entries" => [%{"value" => "1"}]
             })

    assert {:error,
            [
              %ExParamsSchema.ValidationError{path: ["first"], reason: :invalid_first},
              %ExParamsSchema.ValidationError{path: ["payload", "count"], reason: :invalid_count},
              %ExParamsSchema.ValidationError{
                path: ["entries", 0, "value"],
                reason: :invalid_entry_value
              }
            ]} =
             ValidationBoundaryParams.parse_detailed(%{
               "first" => "0",
               "payload" => %{"count" => "0"},
               "entries" => [%{"value" => "0"}]
             })

    assert {:error, :invalid_params} = ValidationBoundaryParams.parse([])

    assert {:error,
            [
              %ExParamsSchema.ValidationError{
                path: [],
                keyword: :cast,
                reason: :invalid_params
              }
            ]} = ValidationBoundaryParams.parse_detailed([])
  end

  test "strict modeの詳細エラーは未知の入力キーのpathと制約を保持する" do
    assert {:error,
            [
              %ExParamsSchema.ValidationError{
                path: ["unknown"],
                keyword: :additional_properties,
                reason: {:unknown_param, "unknown"},
                details: %{key: "unknown"}
              }
            ]} =
             StrictParams.parse_detailed(%{
               "input-id" => "1",
               "profile" => %{"name" => "Ada"},
               "unknown" => "value"
             })
  end

  defp valid_simple_schema_params(overrides) do
    %{
      "fixture-id" => "1",
      "level" => "128",
      "mode" => "merge",
      "ratio" => "1.5",
      "empty" => nil,
      "channels" => ["1"]
    }
    |> Map.merge(overrides)
    |> DslParams.parse()
  end
end
