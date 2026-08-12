# ExParamsSchema

`ExParamsSchema` は、LiveView、Phoenix Controller、JSON API などで受け取る文字列中心の params を、型付きの Elixir 値へ変換・検証するライブラリです。

[English](README.md)

## 特長

- 文字列の整数・boolean・日付・日時を Elixir の値へ変換する
- schema から params 用の構造体、`t/0`、`parse/1` を生成する
- `parse/1`・`parse/2` で任意の params を変換・検証する
- 対応する callback の直前で params を自動変換する統合機能を提供する
- ネストした map・list、既定値、独自型、JSON Schema Draft 7 の制約を扱う

## インストール

`mix.exs` の依存関係に追加して、依存関係を取得します。

```elixir
def deps do
  [
    {:ex_params_schema, "~> 0.1.0"}
  ]
end
```

以下のコマンドで依存関係を更新してください：

```shell
mix deps.get
```

## 基本的な使い方

イベントや HTTP リクエストで受け取る入力ごとに params モジュールを定義します。`defschema` 内の `field/3` から、構造体と `parse/1` が生成されます。

```elixir
defmodule MyAppWeb.Params.Update do
  use ExParamsSchema

  defschema do
    field :id, :integer, minimum: 1, error: :invalid_id
    field :value, :integer, minimum: 0, maximum: 255, error: :invalid_value
    field :enabled, :boolean, default: false
  end
end
```

受け取った params を `parse/1` に渡すと、変換・検証済みの構造体を取得できます。

```elixir
iex> MyAppWeb.Params.Update.parse(%{"id" => "2", "value" => "128", "enabled" => "on"})
{:ok, %MyAppWeb.Params.Update{id: 2, value: 128, enabled: true}}

iex> MyAppWeb.Params.Update.parse(%{"id" => "2", "value" => "256"})
{:error, :invalid_value}
```

`error:` を省略した場合、失敗時は `{:invalid_param, field_name}` を返します。

```elixir
defmodule MyAppWeb.Params.CreateUser do
  use ExParamsSchema

  defschema do
    field :name, :string, min_length: 1
  end
end

iex> MyAppWeb.Params.CreateUser.parse(%{"name" => ""})
{:error, {:invalid_param, :name}}
```

複数の field エラーを UI で扱う場合は、`parse_detailed/1` を使うと path、検証 keyword、詳細を取得できます。

```elixir
iex> {:error, errors} = MyAppWeb.Params.Update.parse_detailed(%{"id" => "0", "value" => "256"})
iex> Enum.map(errors, &{&1.path, &1.keyword, &1.reason, &1.details})
[
  {["id"], :minimum, :invalid_id, %{expected: 1, exclusive?: false}},
  {["value"], :maximum, :invalid_value, %{expected: 255, exclusive?: false}}
]
```

フォーム表示用には `ValidationError.to_form_errors/1` で詳細エラーを field path ごとにまとめられます。

```elixir
iex> ExParamsSchema.ValidationError.to_form_errors(errors)
%{["id"] => [:invalid_id], ["value"] => [:invalid_value]}
```

コンパイル済み schema を使う場合は `ExParamsSchema.parse_detailed/2` を利用します。

```elixir
iex> schema = ExParamsSchema.compile!(%{id: {:integer, minimum: 1}, value: {:integer, minimum: 0, maximum: 255}})
iex> {:error, errors} = ExParamsSchema.parse_detailed(%{"id" => "0", "value" => "256"}, schema)
iex> Enum.map(errors, &{&1.path, &1.keyword, &1.reason})
[
  {["id"], :minimum, {:invalid_param, :id}},
  {["value"], :maximum, {:invalid_param, :value}}
]
```

## 主な設定

| 設定 | 用途 |
| --- | --- |
| `source: "input-id"` | 入力キーを field 名に対応付ける |
| `default: value` | field が未指定のときだけ既定値を使う |
| `optional: true` | 未指定を許可し、`nil` を返す |
| `nullable: true` | 明示的な `nil` を許可する |
| `strict: true` | schema にない入力キーを拒否する |
| `error: :reason` | 変換・検証に失敗したときの理由を指定する |

`optional:`、`nullable:`、`default:` の意味と空文字の扱いは、[パースの仕様](docs/parsing-semantics_ja.md)を参照してください。

## callback との統合

`ExParamsSchema.Handler` を使うと、`@params_schema` を置いた callback の直前で params を変換できます。成功時は callback の `params` に構造体が渡り、失敗時は `on_error:` で指定した関数が呼び出されます。

```elixir
defmodule MyAppWeb.ExampleLive do
  use Phoenix.LiveView
  use ExParamsSchema.Handler, on_error: :handle_params_error

  @params_schema MyAppWeb.Params.Update
  def handle_event("update", params, socket) do
    {:noreply, assign(socket, id: params.id, value: params.value)}
  end

  defp handle_params_error(event, reason, socket) do
    {:noreply, put_flash(socket, :error, "#{event}: #{inspect(reason)}")}
  end
end
```

`handle_event/3` のほか、`handle_params/3` と `handle_info/2` にも対応します。`@params_schema` は直後の callback clause にだけ適用されます。`on_error:` の第1引数は `handle_event/3` ではイベント名、ほかの callback では変換前の params です。対象 callback とエラーハンドラーの仕様は `ExParamsSchema.Handler` の moduledoc を参照してください。

Phoenix Controller や JSON API では、アクション内で params モジュールの `parse/1` を呼び出します。

```elixir
def create(conn, params) do
  with {:ok, input} <- MyAppWeb.Params.Update.parse(params) do
    # input は型変換・検証済みの構造体
    json(conn, %{id: input.id, value: input.value})
  end
end
```

## 構造体を生成しない場合

共通の validation などでは、map 定義を一度コンパイルして `parse/2` に渡せます。

```elixir
schema = ExParamsSchema.compile!(%{
  page: {:integer, minimum: 1, default: 1},
  query: {:string, optional: true}
})

iex> ExParamsSchema.parse(%{"page" => "2"}, schema)
{:ok, %{page: 2, query: nil}}
```

## ドキュメント

- [DSL リファレンス](docs/dsl_ja.md): 型、制約、nested map・list、独自型
- [パースの仕様](docs/parsing-semantics_ja.md): 入力キー、未指定値、strict mode、エラーの返し方
- [`json_schema:` の利用](docs/json-schema-usage_ja.md): DSL では表現できない JSON Schema 制約
- [開発ガイド](docs/development_ja.md): ツールチェーンの準備、Git フック、ローカル CI チェック