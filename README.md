# ExParamsSchema

`ExParamsSchema` converts and validates string-oriented params received by LiveView, Phoenix controllers, JSON APIs, and similar boundaries into typed Elixir values.

[日本語版](README_ja.md)

## Features

- Converts string integers, booleans, dates, and datetimes into Elixir values
- Generates a params struct, `t/0`, and `parse/1` from a schema
- Converts and validates arbitrary params with `parse/1` and `parse/2`
- Provides an integration that converts params immediately before supported callbacks
- Supports nested maps and lists, defaults, custom types, and JSON Schema Draft 7 constraints

## Installation

Add the dependency to `mix.exs` and fetch it:

```elixir
def deps do
  [
    {:ex_params_schema, "~> 0.1.1"}
  ]
end
```

Update your dependencies with:

```shell
mix deps.get
```

## Basic usage

Define a params module for each event or HTTP request input. `field/3` declarations inside `defschema` generate a struct and `parse/1`.

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

Pass received params to `parse/1` to obtain a converted and validated struct:

```elixir
iex> MyAppWeb.Params.Update.parse(%{"id" => "2", "value" => "128", "enabled" => "on"})
{:ok, %MyAppWeb.Params.Update{id: 2, value: 128, enabled: true}}

iex> MyAppWeb.Params.Update.parse(%{"id" => "2", "value" => "256"})
{:error, :invalid_value}
```

When `error:` is omitted, failures return `{:invalid_param, field_name}`.

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

For UIs that need to handle multiple field errors, use `parse_detailed/1` to receive each error's path, validation keyword, and details.

```elixir
iex> {:error, errors} = MyAppWeb.Params.Update.parse_detailed(%{"id" => "0", "value" => "256"})
iex> Enum.map(errors, &{&1.path, &1.keyword, &1.reason, &1.details})
[
  {["id"], :minimum, :invalid_id, %{expected: 1, exclusive?: false}},
  {["value"], :maximum, :invalid_value, %{expected: 255, exclusive?: false}}
]
```

Group detailed errors by field path for form rendering with `ValidationError.to_form_errors/1`.

```elixir
iex> ExParamsSchema.ValidationError.to_form_errors(errors)
%{["id"] => [:invalid_id], ["value"] => [:invalid_value]}
```

Use `ExParamsSchema.parse_detailed/2` with a compiled schema:

```elixir
iex> schema = ExParamsSchema.compile!(%{id: {:integer, minimum: 1}, value: {:integer, minimum: 0, maximum: 255}})
iex> {:error, errors} = ExParamsSchema.parse_detailed(%{"id" => "0", "value" => "256"}, schema)
iex> Enum.map(errors, &{&1.path, &1.keyword, &1.reason})
[
  {["id"], :minimum, {:invalid_param, :id}},
  {["value"], :maximum, {:invalid_param, :value}}
]
```

## Main options

| Option | Purpose |
| --- | --- |
| `source: "input-id"` | Maps an input key to a field name |
| `default: value` | Uses a default only when the field is absent |
| `optional: true` | Allows an absent field and returns `nil` |
| `nullable: true` | Allows an explicit `nil` |
| `strict: true` | Rejects input keys that are not in the schema |
| `error: :reason` | Sets the reason returned on conversion or validation failure |

See [parsing semantics](docs/parsing-semantics.md) for the meanings of `optional:`, `nullable:`, and `default:`, including how empty strings are handled.

## Callback integration

`ExParamsSchema.Handler` converts params immediately before callbacks that have an `@params_schema`. On success, the callback receives a struct as `params`; on failure, the function specified by `on_error:` is called.

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

`handle_params/3` and `handle_info/2` are supported in addition to `handle_event/3`. An `@params_schema` applies only to the callback clause immediately following it. The first `on_error:` argument is the event name for `handle_event/3`, and the original params for the other callbacks. See the `ExParamsSchema.Handler` moduledoc for supported callbacks and error-handler behavior.

In Phoenix controllers and JSON APIs, call a params module's `parse/1` inside the action.

```elixir
def create(conn, params) do
  with {:ok, input} <- MyAppWeb.Params.Update.parse(params) do
    # input is a converted and validated struct
    json(conn, %{id: input.id, value: input.value})
  end
end
```

## Without generating a struct

For shared validations and similar use cases, compile a map definition once and pass it to `parse/2`.

```elixir
schema = ExParamsSchema.compile!(%{
  page: {:integer, minimum: 1, default: 1},
  query: {:string, optional: true}
})

iex> ExParamsSchema.parse(%{"page" => "2"}, schema)
{:ok, %{page: 2, query: nil}}
```

## Documentation

- [DSL reference](docs/dsl.md): types, constraints, nested maps and lists, and custom types
- [Parsing semantics](docs/parsing-semantics.md): input keys, absent values, strict mode, and errors
- [Using `json_schema:`](docs/json-schema-usage.md): JSON Schema constraints that cannot be expressed with the DSL
- [Development guide](docs/development.md): toolchain setup, Git hooks, and local CI checks
