# Development

This page describes the local development workflow for `ExParamsSchema`.

[日本語版](development_ja.md)

## Toolchain

The project pins Erlang, Elixir, [prek](https://prek.j178.dev/), and [typos](https://github.com/crate-ci/typos) in `mise.toml`. Install the toolchain after cloning:

```shell
mise install
```

Fetch the Mix dependencies separately:

```shell
mix deps.get
```

Keeping these steps separate makes it clear whether a failure is in the toolchain installation or dependency resolution.

## Git hooks

`prek` runs the following checks before a commit:

- `mix format --check-formatted`
- `typos`
- `mix credo --strict`
- `mix compile --warnings-as-errors`
- `mix dialyzer`
- `mix test --cover --warnings-as-errors`

Enable the hook once for the local clone:

```shell
mise exec -- prek install
```

Run all configured hooks against every tracked file without creating a commit:

```shell
mise exec -- prek run --all-files
```

## Full CI suite

Run the complete CI suite locally before opening a pull request:

```shell
mise run ci
```

In addition to the pre-commit checks, this generates the documentation with `mix docs`.
