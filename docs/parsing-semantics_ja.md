# パースの仕様

このページでは、`parse/1` と `parse/2` が受け取る入力、型変換、検証、エラーの返し方を説明します。
型と field option の一覧は [DSL リファレンス](dsl_ja.md)を参照してください。

[English](parsing-semantics.md)

## 入力キー

各フィールドの入力キーは`source:`で指定する。`source:`には文字列または atom を指定でき、`defschema`
ブロック内の `field/3` と map 形式の定義の両方で利用できる。

入力値は次の優先順位で取得する。

1. `source:`で指定されたキー。未指定時はフィールド名の文字列
2. schemaで宣言されたフィールド名のatom

両方のキーが入力mapに存在する場合は、文字列または`source:`で指定されたキーを優先する。

schemaに存在しない入力フィールドは既定では無視する。LiveView や HTTP リクエストでフレームワークなどが
付加する補助パラメーターを受け取れるようにするため、出力構造体にも未知の値は保持しない。

`defschema strict: true do ... end` または `compile!/2` に `strict: true` を指定すると、トップレベルの未知キーを
`{:unknown_param, key}` として拒否する。`use ExParamsSchema, strict: true` はそのモジュールの既定値を
設定する。入れ子の map に指定する `strict: true` はそのmapだけを対象とし、未知キーは最も近い
`error:`（なければ親フィールドの標準エラー）で返す。strictなobjectはJSON Schemaにも
`"additionalProperties": false` として出力する。

## 未指定値、空文字、default

フィールドが未指定の場合は次の順序で処理する。

1. `default:`があればdefaultを使用する
2. `optional: true`であれば`nil`を使用する
3. それ以外はフィールドのエラーを返す

`optional: true`のフィールドに`nil`または空文字が明示的に渡された場合は`nil`とする。
`:string`フィールドでは、空白だけの文字列も`nil`とする。この場合はdefaultを適用しない。
defaultはフィールド自体が未指定の場合だけ適用する。

defaultはschema定義時に型変換と制約検証を行う。不正なdefaultを持つparamsモジュールは
コンパイルできない。正規化済みdefaultは`parse/1`と`defstruct`の両方で使用する。

## nullable

`nullable: true`は、フィールドが存在して値が`nil`の場合に、その値を受け入れる指定である。
フィールドの未指定を許可する`optional: true`とは別の意味を持つ。

## 型変換と検証

入力値は宣言された型へ変換した後、生成済みのJSON Schemaで検証する。

```text
入力キー解決
  → 未指定値と空文字の処理
  → 型変換
  → JSON Schema検証
  → 構造体生成
```

`:string` は型変換時に前後の空白を除去し、`min_length:`などの制約は除去後の文字列へ適用する。
それ以外の組み込み型は入力文字列の空白を除去しない。たとえば `:integer`、`:float`、`:number`、
`:boolean` は `" 12 "` や `"true "` を受け付けない。独自型の空白処理は adapter の `cast/2` に従う。

`:date` は ISO 8601 の日付文字列を `Date` へ変換する。`:datetime` はタイムゾーンを含む ISO 8601
の日時文字列を受け入れ、UTC の `DateTime` へ正規化する。タイムゾーンのない日時は受け入れない。
いずれも `Date` / `DateTime` の値を直接渡せ、`default:` にも同じ変換規則を適用する。

## schema定義エラー

次の問題はparamsのparse時ではなく、schema定義時に`ArgumentError`として報告する。

- 未知または重複したoption
- 同一階層の重複したフィールド名
- 未対応の型
- `minimum:`をstringへ指定するなど、型に適用できない制約
- option値の型が不正
- minimumとmaximumなどの境界が逆転している
- atom enumが空、またはatom以外を含む
- list itemへ`optional:`などフィールド専用optionを指定している
- defaultを宣言された型へ変換できない、またはdefaultが制約を満たさない
- `enum:`または`in:`の要素が、型変換後のフィールド値と型互換でない

`in:`には、コンパイル時に有限であると判断できるlist、Range、MapSetだけを指定できる。
任意のEnumerableやStreamは受け付けない。

`enum:`と`in:`の要素は、JSON Schemaで型変換後の値と比較されるため、対象型と同じ型で指定する。
`:any`は任意の非nil値を許可し、`nil`は`nullable: true`または`:null`でのみ許可する。atom enumには
`enum:`と`in:`を追加できない。

## エラー

castまたは検証に失敗した場合、フィールドの`error:`を返す。省略時は
`{:invalid_param, field_name}`を返す。

ネストした値では最も近い`error:`を使用する。複数のJSON Schemaエラーがある場合は、
順序を保持できるkeyword listで宣言されたフィールドを宣言順に扱う。mapで宣言された
ネストフィールド間の順序は保証しない。

## 詳細エラー

`parse_detailed/1` と `parse_detailed/2` は、通常の `parse` と同じ成功値を返し、失敗時には
`ExParamsSchema.ValidationError` の list を返す。各エラーは `path`（map の文字列キーと list の
整数添字）、`keyword`、`reason`、`details` を持つ。`reason` は通常の `parse` が返す `error:` と
同じ値である。

JSON Schema 検証で複数の違反があれば、それぞれのエラーを返す。一方、必須値の欠損、型変換、
strict mode の未知キーは変換段階で検出されるため、最初のエラーだけを返す。これらの `keyword` は
それぞれ `:cast` または `:additional_properties` となる。
