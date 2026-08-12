defmodule ExParamsSchema do
  @moduledoc """
  LiveView、Phoenix Controller、JSON API などで受け取る文字列中心の params を検証し、
  型付き構造体へ変換するための DSL です。

  `use ExParamsSchema` を指定したモジュールで `defschema/1`・`defschema/2` のブロック内に
  `field/2`・`field/3` を
  使うと、構造体、`t/0`、`parse/1` が生成されます。

      defmodule ExampleParams do
        use ExParamsSchema

        defschema do
          field :id, :integer, minimum: 1, maximum: 24
          field :value, :integer, minimum: 0, maximum: 255
        end
      end

      ExampleParams.parse(%{"id" => "1", "value" => "128"})
      #=> {:ok, %ExampleParams{id: 1, value: 128}}

  `:boolean`、`:date`、`:datetime`、`:integer`、`:float`、`:number`、`:string`、`:null`、`:any`、atom enum、
  map、list を組み合わせられます。文字列は型変換してから JSON Schema Draft 7 による標準制約の
  検証を行います。詳細は README と `docs/` を参照してください。
  """

  alias ExParamsSchema.{Compiler, Definition, Schema}
  alias ExParamsSchema.Schema.Options

  @typedoc "実行時に確定するフィールド値です。"
  @type value :: dynamic()

  @typedoc "呼び出し側が任意に指定できるエラー理由です。"
  @type error_reason :: dynamic()

  @typedoc "`parse_detailed/1`・`parse_detailed/2` が返す、フィールド単位の検証エラーです。"
  @type validation_error :: ExParamsSchema.ValidationError.t()

  @typedoc "`compile!/1` が返す、再利用可能なコンパイル済みスキーマです。"
  @opaque compiled_schema :: %{required(:__struct__) => module(), optional(atom()) => term()}

  @type scalar_field_type ::
          :any
          | :boolean
          | :date
          | :datetime
          | :float
          | :integer
          | :null
          | :number
          | :string

  @type atom_enum_type :: {kind :: :enum, allowed_values :: [atom()]}
  @type custom_field_type :: {kind :: :custom, module :: module(), options :: keyword()}
  @type object_field_type :: %{optional(field_name()) => definition()}
  @type array_field_type :: [definition()]

  @type field_type ::
          scalar_field_type()
          | atom_enum_type()
          | custom_field_type()
          | object_field_type()
          | array_field_type()

  @type definition_with_options :: {field_type :: field_type(), options :: field_options()}
  @type custom_definition :: {module :: module(), options :: keyword()}
  @type definition :: field_type() | definition_with_options() | custom_definition()

  @type field_options :: [
          source: String.t() | atom(),
          in: [value()] | Range.t() | MapSet.t(),
          enum: [value()],
          minimum: number(),
          maximum: number(),
          min_length: non_neg_integer(),
          max_length: non_neg_integer(),
          pattern: String.t(),
          format: String.t(),
          min_items: non_neg_integer(),
          max_items: non_neg_integer(),
          unique_items: boolean(),
          json_schema: map() | boolean(),
          nullable: boolean(),
          optional: boolean(),
          strict: boolean(),
          default: value(),
          error: error_reason()
        ]

  @type field_name :: atom()
  @type field :: {name :: field_name(), type :: field_type(), options :: field_options()}
  @type schema_definition :: %{required(field_name()) => definition()}
  @type schema_options :: keyword()
  @type parsed_params :: map()
  @type parse_result :: {:ok, params :: parsed_params()} | {:error, reason :: error_reason()}
  @type detailed_parse_result ::
          {:ok, params :: parsed_params()} | {:error, errors :: [validation_error()]}

  @doc """
  params モジュールでスキーマ DSL を利用できるようにします。

  `defschema/1`・`defschema/2` と `field/2`・`field/3` を import します。コンパイル時に
  宣言を検証し、構造体、`t/0`、`parse/1` を生成します。
  """
  defmacro __using__(options) do
    schema_options = Options.normalize!(options, "use ExParamsSchema")

    quote do
      import ExParamsSchema, only: [defschema: 1, defschema: 2, field: 2, field: 3]

      Module.register_attribute(__MODULE__, :event_param_fields, accumulate: true)
      @event_param_strict unquote(schema_options.strict)
      @before_compile ExParamsSchema
    end
  end

  @doc """
  オプション付きで 1 フィールドを宣言します。

      field :id, :integer,
        source: "input-id",
        minimum: 1,
        error: :invalid_id

  `source:` は入力キーを指定します。`optional:`、`nullable:`、`default:`、`error:` は
  フィールドに指定できます。型ごとの制約は README を参照してください。

  ## コンパイル時エラー

  未対応の型、未知または重複した option、不正な option 値、型に適用できない制約、重複した
  フィールド名または入力キー、制約を満たさない `default:` は `ArgumentError` になります。
  """
  defmacro field(name, type, options \\ []) do
    quote bind_quoted: [name: name, type: type, options: options] do
      @event_param_fields {name, type, options}
    end
  end

  @doc """
  スキーマを宣言します。

      defschema do
        field :page, :integer, default: 1, minimum: 1
        field :query, :string, optional: true
      end

  ブロック内で `field/2` または `field/3` によりフィールドを宣言します。同じフィールド名や同じ
  入力キーを重複して宣言できません。`use ExParamsSchema, strict: true` を指定している場合は、
  その strict mode を引き継ぎます。

  `strict:` を指定すると、`use ExParamsSchema` の設定をスキーマ単位で上書きできます。

      defschema strict: true do
        field :identifier, :integer
      end

  `strict: true` の場合、未知の入力キーを拒否します。

  ## コンパイル時エラー

  `strict:` 以外の option、フィールド定義の不正な型・option・制約・default は
  `ArgumentError` になります。
  """
  defmacro defschema(options \\ [], do: block) do
    quote do
      ExParamsSchema.configure_defschema!(__MODULE__, unquote(options))
      unquote(block)
    end
  end

  @doc false
  @spec configure_defschema!(module(), keyword()) :: :ok
  def configure_defschema!(module, options) do
    default_options = %Options{
      strict: Module.get_attribute(module, :event_param_strict, false)
    }

    schema_options = Options.normalize!(options, "defschema", default_options)

    Module.put_attribute(module, :event_param_strict, schema_options.strict)
  end

  @doc """
  スキーマ定義の map を実行用スキーマへコンパイルします。

      iex> schema = ExParamsSchema.compile!(%{
      ...>   id: {:integer, source: "input-id", minimum: 1},
      ...>   enabled: {:boolean, default: false}
      ...> })
      iex> ExParamsSchema.parse(%{"input-id" => "1", "enabled" => "true"}, schema)
      {:ok, %{enabled: true, id: 1}}

  生成したスキーマは `parse/2` へ渡します。これは `ExParamsSchema.Handler` で、構造体を
  生成せず map を受け取りたい場合にも使用します。

  ## 例外

  定義が不正な場合は `ArgumentError` になります。キーは atom で指定してください。
  """
  @spec compile!(schema_definition(), schema_options()) :: compiled_schema()
  def compile!(definition, options \\ []) when is_map(definition) and is_list(options) do
    {fields, schema_options} = compile_schema_definition!(definition, options, "compile!")

    Schema.compile!(fields, schema_options.strict)
  end

  @doc """
  コンパイル済みスキーマまたは map 形式のフィールド定義から JSON Schema Draft 7 を返します。

      iex> ExParamsSchema.json_schema(%{count: {:integer, minimum: 1}})
      ...> |> get_in(["properties", "count"])
      %{"minimum" => 1, "type" => "integer"}

  map 形式の定義を渡す場合は `compile!/1` を必要としません。`strict: true` を指定する場合は
  `json_schema(definition, strict: true)` を使います。
  `defschema` を使うモジュールでは、生成される `json_schema/0` で引数なしに取得できます。
  """
  @spec json_schema(compiled_schema()) :: map()
  @spec json_schema(schema_definition()) :: map()
  @spec json_schema(schema_definition(), schema_options()) :: map()
  def json_schema(schema_or_definition, options \\ [])

  def json_schema(%Schema{} = schema, _) do
    Schema.json_schema(schema)
  end

  def json_schema(definition, options)
      when is_map(definition) and not is_struct(definition) and is_list(options) do
    {fields, schema_options} = compile_schema_definition!(definition, options, "json_schema")

    Schema.json_schema(fields, schema_options.strict)
  end

  @doc """
  コンパイル済みスキーマでパラメーターを検証・変換します。

      iex> schema = ExParamsSchema.compile!(%{count: {:integer, minimum: 1}})
      iex> ExParamsSchema.parse(%{"count" => "2"}, schema)
      {:ok, %{count: 2}}

  成功時は変換済みの map、失敗時はフィールドの `error:`、または省略時の
  `{:invalid_param, field_name}` を返します。map 以外の入力には `{:error, :invalid_params}` を
  返します。
  """
  @spec parse(map(), compiled_schema()) :: parse_result()
  defdelegate parse(params, schema), to: ExParamsSchema.Parser

  @doc """
  コンパイル済みスキーマでパラメーターを検証・変換し、失敗時に全ての検証エラーを返します。

      iex> schema = ExParamsSchema.compile!(%{count: {:integer, minimum: 1}})
      iex> match?(
      ...>   {:error, [%ExParamsSchema.ValidationError{path: ["count"], keyword: :minimum}]},
      ...>   ExParamsSchema.parse_detailed(%{"count" => "0"}, schema)
      ...> )
      true

  各エラーの `path`、`keyword`、`reason` を UI のフィールドメッセージに利用できます。
  `reason` は通常の `parse/2` と同じ `error:` の値です。型変換、必須値の読み取り、strict mode の
  未知キーも、すべてのフィールド・入れ子の object・array 要素から収集します。型変換エラーの
  `keyword` は `:cast`、未知キーの `keyword` は `:additional_properties` です。
  """
  @spec parse_detailed(map(), compiled_schema()) :: detailed_parse_result()
  defdelegate parse_detailed(params, schema), to: ExParamsSchema.Parser

  defmacro __before_compile__(environment) do
    Compiler.before_compile(environment)
  end

  @type compiled_schema_definition :: {fields :: [Definition.Field.t()], options :: Options.t()}

  @spec compile_schema_definition!(schema_definition(), schema_options(), String.t()) ::
          compiled_schema_definition()
  defp compile_schema_definition!(definition, options, function_name) do
    fields = Definition.compile!(definition)
    schema_options = Options.normalize!(options, function_name)

    {fields, schema_options}
  end
end
