# `json_schema:` の使い方

`json_schema:` は、DSL だけでは表現できない JSON Schema Draft 7 の検証制約を追加するための
option です。入力値の型変換、入力キーの対応付け、構造体・map の生成は DSL が担当し、
`json_schema:` は変換後の値の検証だけを拡張します。

[English](json-schema-usage.md)

## 基本例

`multipleOf` や `exclusiveMinimum` のように DSL にない制約は、追加の JSON Schema で指定できます。

```elixir
defschema do
  field :step, :number,
    minimum: 0,
    json_schema: %{
      "multipleOf" => 0.5,
      "exclusiveMinimum" => 1
    },
    error: :invalid_step
end
```

この例では、`"1.5"` は `1.5` へ変換されて成功し、`"1.0"` は
`:invalid_step` を返します。`minimum: 0` と追加の JSON Schema の制約は両方検証されます。

## マージ順序と上書き

各フィールドの JSON Schema は次の順序で構築します。

1. DSL の型から `"type"` を生成する
2. DSL の標準制約（`minimum:`、`min_length:`、`items`、`properties` など）を追加する
3. `json_schema:` の map を再帰的にマージする
4. `nullable: true` の場合、最終的な `"type"` に `"null"` を追加する

同じ key がある場合、両方の値が map ならその内側も再帰的にマージし、それ以外は追加の JSON Schema が
DSL の生成値を上書きします。したがって、`"properties"` や map 形式の `"items"` に制約を追加しても、
DSL が生成した型や兄弟プロパティは維持されます。`"required"` のような配列、スカラー、boolean schema は
追加側の値で置き換えます。

```elixir
defschema do
  field :payload, :any,
    json_schema: %{
      "type" => "object",
      "additionalProperties" => false,
      "properties" => %{"kind" => %{"const" => "fixed"}},
      "required" => ["kind"]
    },
    error: :invalid_payload
end
```

追加の JSON Schema は `"type"` も上書きできます。ただし DSL の型変換は変更されません。たとえば
`:integer` に `"type" => "string"` を重ねても、入力は先に整数へ変換されるため、通常は検証と
矛盾します。型、`properties`、`items` を追加の JSON Schema で定義する場合は、原則として `:any` を
使い、入力値をそのまま JSON Schema へ渡してください。

`nullable: true` と追加の JSON Schema の `"type"` を併用すると、上書き後の type に `"null"` を追加します。
type がすでに配列の場合も、既存の型を保ったまま `"null"` を重複なく追加します。`json_schema: false`
は、そのフィールドが入力に存在するときに拒否する boolean schema にし、`nullable:` を適用しません。
`optional: true` のフィールドが未指定の場合は、JSON Schema 検証の対象外となるため成功します。
`json_schema: true` は DSL 生成 schema をそのまま使います。

## DSL と JSON Schema の役割

| 機能 | 担当 |
| --- | --- |
| 文字列から整数・boolean・atom enum への変換 | DSL |
| `source:` による入力キーの対応付け | DSL |
| `optional:`、`default:`、構造体・map の生成 | DSL |
| 範囲、長さ、配列、論理制約、`$ref` の検証 | JSON Schema |
| 失敗時に返す `error:` の選択 | DSL |

DSL の map は宣言済みの子フィールドだけを出力し、未知キーを捨てます。そのため DSL の map に
追加の JSON Schema で新しい `properties` や `required` を追加しても、その入力を型変換処理が保持するわけでは
ありません。任意形状の object、tuple 形式の配列、`additionalProperties` を厳密に検証する用途では、
`:any` と追加の JSON Schema を組み合わせるのが安全です。

追加の JSON Schema 内のエラーも、フィールド自身または最も近い入れ子の `error:` に変換されます。通常の `parse`
は最初の `reason` だけを返します。`parse_detailed` は JSON Schema validator の keyword、path、複数エラーを
`ExParamsSchema.ValidationError` の list として返します。

## Draft 7 と `format:`

ルート schema の `$schema` は JSON Schema Draft 7 です。検証と `$ref` の resolve は
`ex_json_schema`（対応範囲は `~> 0.11.4`）へ委譲します。そのため Draft 7 外の keyword や、
依存ライブラリが実装していない keyword の結果は保証しません。依存ライブラリを更新するときは、
追加の JSON Schema を使う制約を回帰テストしてください。

DSL の `format:` は `:string` にだけ指定できます。追加の JSON Schema 内の `"format"` も validator へ渡され、
対応する format の検証範囲は `ex_json_schema` のバージョンとアプリケーション設定に従います。
このライブラリは `ExJsonSchema.Schema.resolve/2` の個別の custom format validator を設定しません。
独自 format を使う場合は `ex_json_schema` のアプリケーション設定を行い、期待する値を必ずテストして
ください。

## 推奨事項

- DSL で表現できる型・標準制約は DSL で宣言する。
- `multipleOf`、`contains`、`anyOf`、`not`、`additionalProperties` などの追加制約には、追加の JSON Schema を使う。
- DSL の型変換と矛盾する `type`、配列形式の `items`、`required` を上書きする場合は `:any` を使う。
- `json_schema: false` は、存在する入力を明示的に禁止する場合だけに使う。未指定も拒否する場合は
  `optional: true` を併用しない。
- 追加の JSON Schema を変更したら、成功値と失敗値の両方をテストする。
