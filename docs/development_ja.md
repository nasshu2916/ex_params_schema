# Development

このページでは `ExParamsSchema` のローカル開発手順を説明します。

[English](development.md)

## Toolchain

このプロジェクトでは、Erlang、Elixir、[prek](https://prek.j178.dev/)、[typos](https://github.com/crate-ci/typos) のバージョンを `mise.toml` で固定しています。clone 後にツールチェーンをインストールします。

```shell
mise install
```

Mix の依存関係は別途取得します。

```shell
mix deps.get
```

手順を分けることで、ツールチェーンのインストールと依存関係の解決を個別に切り分けられます。

## Git フック

`prek` はコミット前に、次のチェックを実行します。

- `mix format --check-formatted`
- `typos`
- `mix credo --strict`
- `mix compile --warnings-as-errors`
- `mix dialyzer`
- `mix test --cover --warnings-as-errors`

ローカル clone で一度だけ Git フックを有効化します。

```shell
mise exec -- prek install
```

コミットを作成せず、追跡対象のすべてのファイルに設定済みフックを実行するには次を使います。

```shell
mise exec -- prek run --all-files
```

## 完全な CI スイート

プルリクエストを作成する前に、ローカルで完全な CI スイートを実行できます。

```shell
mise run ci
```

このコマンドは、コミット前チェックに加えて `mix docs` によるドキュメント生成も実行します。
