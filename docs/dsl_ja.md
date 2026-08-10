# DSL リファレンス

このページでは `ExParamsSchema` の宣言形式、型、field option を説明します。入力の解決順序、
未指定値、型変換、エラーの動作は [parse の仕様](parsing-semantics_ja.md)を参照してください。

[English](dsl.md)

## スキーマの宣言

params モジュールでは `use ExParamsSchema` の後に `defschema` と `field/3` を使います。`defschema` を
省略して、モジュール直下に `field/3` を並べることもできます。

```elixir
defmodule MyApp.Params.Search do
  use ExParamsSchema

  defschema strict: true do
    field :page, :integer, source: "page", minimum: 1, default: 1
    field :query, :string, optional: true
  end
end
```

`use ExParamsSchema, strict: true` はモジュールの既定を設定し、`defschema strict: false` または
`defschema strict: true` はその既定を上書きします。`strict:` の詳細は [parse の仕様](parsing-semantics_ja.md#入力キー)を参照してください。

構造体を生成しない場合は map 定義を `compile!/2` に渡します。

```elixir
schema = ExParamsSchema.compile!(%{
  page: {:integer, minimum: 1, default: 1},
  query: {:string, optional: true}
}, strict: true)
```

map 定義のキーは atom にします。型と field option は `{type, options}` で組み合わせます。

### 複数の `defschema`

`defschema` はモジュール内のスキーマを区切りません。複数回呼び出した場合、各ブロックで宣言した
field は 1 つのスキーマとして結合され、生成される構造体、`parse/1`、`json_schema/0` も共通です。

```elixir
defmodule MyApp.Params.Search do
  use ExParamsSchema

  defschema do
    field :page, :integer
  end

  defschema do
    field :query, :string
  end
end
```

この例では `page` と `query` の両方を持つスキーマになります。同じ field 名または同じ入力キーを
重複して宣言すると、コンパイル時エラーになります。`strict:` はスキーマ全体の設定であり、複数の
`defschema` に指定した場合は最後の指定が全 field に適用されます。

## 組み込み型

| 型 | 変換後の値 | 主な制約 |
| --- | --- | --- |
| `:boolean` | `true` / `false` | `enum:`、`in:` |
| `:date` | `Date.t()` | — |
| `:datetime` | UTC の `DateTime.t()` | — |
| `:integer` | 整数 | `minimum:`、`maximum:`、`enum:`、`in:` |
| `:float` | 浮動小数点数 | `minimum:`、`maximum:`、`enum:`、`in:` |
| `:number` | 整数または浮動小数点数 | `minimum:`、`maximum:`、`enum:`、`in:` |
| `:string` | 前後の空白を除去した文字列 | `min_length:`、`max_length:`、`pattern:`、`format:`、`enum:`、`in:` |
| `:null` | `nil` | `enum:`、`in:` |
| `:any` | 非 `nil` の入力値 | `enum:`、`in:` |
| `{:enum, [:a, :b]}` | 許可した atom | — |
| `%{field: type}` | map | 子フィールドの定義 |
| `[type]` | list | `min_items:`、`max_items:`、`unique_items:` |

宣言例です。

```elixir
defschema do
  field :mode, {:enum, [:merge, :replace]}
  field :label, :string, min_length: 2, max_length: 40
  field :channels, [{:integer, minimum: 1, maximum: 512}], min_items: 1
  field :position, %{x: :integer, y: :integer}, nullable: true
end
```

組み込み型の文字列表現と日付・日時の変換規則は [parse の仕様](parsing-semantics_ja.md#型変換と検証)を参照してください。

## field option

| option | 対象 | 用途 |
| --- | --- | --- |
| `source:` | フィールド | 入力キーを対応付ける |
| `minimum:` / `maximum:` | `:integer`、`:float`、`:number` | 数値の下限・上限を検証する |
| `min_length:` / `max_length:` | `:string` | 文字列長を検証する |
| `pattern:` / `format:` | `:string` | JSON Schema のパターン・format を検証する |
| `min_items:` / `max_items:` / `unique_items:` | list | 要素数・重複を検証する |
| `enum:` / `in:` | scalar 型（atom enum を除く） | 許可する値を制限する |
| `nullable:` / `optional:` / `default:` | フィールド | `nil`、未指定、既定値を制御する |
| `strict:` | map | map 内の未知キーを拒否する |
| `error:` | フィールドまたは入れ子の値 | 失敗時に返す理由を指定する |
| `json_schema:` | すべての型 | 追加の JSON Schema を指定、または `false` を指定する |

`enum:` と `in:` の要素は変換後の値と同じ型で指定します。`in:` には有限の list、`Range`、`MapSet` を
指定できます。`json_schema:` のマージ規則と用途は [`json_schema:` の使い方](json-schema-usage_ja.md)を
参照してください。

## 独自型

`ExParamsSchema.Type` を実装する module は `{Module, options}` として型に指定できます。adapter は入力を
ドメイン値へ変換し、`to_json/2` で JSON Schema が検証できる JSON 互換の値へ変換します。したがって、
独自型はアプリケーションで扱いやすい値を返しつつ、標準の field option による制約も利用できます。

```text
入力値 → cast/2 → adapter の値 → validate/2（任意）
    → to_json/2 → JSON Schema の検証 → params 構造体
```

`cast/2` と `validate/2` は型固有の変換・検証を担当します。`minimum:`、`min_length:`、`pattern:`
などの field option は、`to_json/2` の戻り値と `json_schema/1` が返す JSON Schema に対して適用されます。
たとえば金額を `%{cents: integer()}` として扱う場合は、`to_json/2` で整数へ変換することで
`minimum:` を金額（セント）に適用できます。

```elixir
defmodule MyApp.PriceType do
  @behaviour ExParamsSchema.Type

  @type t :: %{cents: non_neg_integer()}

  def cast(value, _options) do
    case Integer.parse(value) do
      {cents, ""} when cents >= 0 -> {:ok, %{cents: cents}}
      _other -> {:error, :invalid_price}
    end
  end

  def to_json(%{cents: cents}, _options), do: cents
  def json_schema(_options), do: %{"type" => "integer"}
end

field :price, {MyApp.PriceType, []}, minimum: 0, error: :invalid_price
```

### adapter option と field option

`{Module, options}` の `options` は adapter 専用です。上の例の `minimum:`、`error:` は field option
なので、tuple の外側に指定します。adapter option は `cast/2`、`to_json/2`、`json_schema/1`、
`validate/2` にそのまま渡されます。

```elixir
field :price,
  {MyApp.PriceType, currency: :jpy, minimum_cents: 100},
  minimum: 100,
  error: :invalid_price
```

adapter 固有の option を受け付ける場合は、`validate_options/1` を実装してください。schema の定義時に
呼ばれるため、未知の option や不正な値を parse 時ではなく早期に検出できます。

```elixir
@impl true
def validate_options(options) do
  if Keyword.keyword?(options) and options[:currency] in [:jpy, :usd] do
    :ok
  else
    {:error, "currency must be :jpy or :usd"}
  end
end
```

### callback の仕様

| callback | 必須 | 戻り値と用途 |
| --- | --- | --- |
| `cast(input, options)` | TRUE | `{:ok, value}` または `{:error, detail}`。外部入力を adapter の値へ変換する |
| `to_json(value, options)` | TRUE | JSON 互換の値。field option と JSON Schema 検証に使用する |
| `json_schema(options)` | TRUE | 追加する JSON Schema の map、または常に拒否する `false` |
| `validate(value, options)` | FALSE | `:ok` または `{:error, detail}`。変換後の値に型固有の制約を適用する |
| `validate_options(options)` | FALSE | `:ok` または `{:error, message}`。adapter option を schema 定義時に検証する |
| `typespec()` | FALSE | 生成される params 構造体のフィールド型を表す AST |

`cast/2` または `validate/2` が `{:error, detail}` を返したとき、`detail` は外部には返されず、
フィールドの `error:`（省略時は `{:invalid_param, field_name}`）に正規化されます。詳細な失敗理由を
利用者へ公開したい場合は、adapter の `detail` ではなく field の `error:` を設定してください。

`typespec/0` を省略した場合、adapter が struct ならその `t/0` を参照します。struct 以外の adapter は
`dynamic()` になります。`typespec/0` を実装すれば、文字列などのプリミティブ値も正確に表せます。

callback の完全な型定義は `ExParamsSchema.Type` の moduledoc を参照してください。入力値の前後空白を
どう扱うかは adapter の `cast/2` が決めます。組み込み型との違いを含むパース順序は
[parse の仕様](parsing-semantics_ja.md#型変換と検証)を参照してください。

## JSON Schema の出力

`json_schema/0` または `ExParamsSchema.json_schema/1` は、宣言から生成した JSON Schema Draft 7 を返します。

```elixir
iex> ExParamsSchema.json_schema(%{count: {:integer, minimum: 1}})
...> |> get_in(["properties", "count"])
%{"minimum" => 1, "type" => "integer"}
```
