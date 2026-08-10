# DSL reference

This page describes `ExParamsSchema` declarations, types, and field options. See [parsing semantics](parsing-semantics.md) for input resolution, absent values, conversion, and errors.

[日本語版](dsl_ja.md)

## Declaring a schema

In a params module, use `defschema` and `field/3` after `use ExParamsSchema`. You can also omit `defschema` and place `field/3` declarations directly in the module.

```elixir
defmodule MyApp.Params.Search do
  use ExParamsSchema

  defschema strict: true do
    field :page, :integer, source: "page", minimum: 1, default: 1
    field :query, :string, optional: true
  end
end
```

`use ExParamsSchema, strict: true` sets a module default. `defschema strict: false` and `defschema strict: true` override that default. See [parsing semantics](parsing-semantics.md#input-keys) for `strict:` details.

To avoid generating a struct, pass a map definition to `compile!/2`.

```elixir
schema = ExParamsSchema.compile!(%{
  page: {:integer, minimum: 1, default: 1},
  query: {:string, optional: true}
}, strict: true)
```

Map-definition keys must be atoms. Combine a type and field options as `{type, options}`.

### Multiple `defschema` blocks

`defschema` does not delimit schemas within a module. When called more than once, fields declared in every block are combined into one schema; the generated struct, `parse/1`, and `json_schema/0` are shared.

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

This example defines one schema with both `page` and `query`. Declaring the same field name or input key twice is a compile-time error. `strict:` is a schema-wide setting; when supplied in multiple `defschema` blocks, its last value applies to every field.

## Built-in types

| Type | Converted value | Main constraints |
| --- | --- | --- |
| `:boolean` | `true` / `false` | `enum:`, `in:` |
| `:date` | `Date.t()` | — |
| `:datetime` | UTC `DateTime.t()` | — |
| `:integer` | integer | `minimum:`, `maximum:`, `enum:`, `in:` |
| `:float` | floating-point number | `minimum:`, `maximum:`, `enum:`, `in:` |
| `:number` | integer or floating-point number | `minimum:`, `maximum:`, `enum:`, `in:` |
| `:string` | string with surrounding whitespace removed | `min_length:`, `max_length:`, `pattern:`, `format:`, `enum:`, `in:` |
| `:null` | `nil` | `enum:`, `in:` |
| `:any` | any non-`nil` input value | `enum:`, `in:` |
| `{:enum, [:a, :b]}` | permitted atom | — |
| `%{field: type}` | map | child-field definitions |
| `[type]` | list | `min_items:`, `max_items:`, `unique_items:` |

For example:

```elixir
defschema do
  field :mode, {:enum, [:merge, :replace]}
  field :label, :string, min_length: 2, max_length: 40
  field :channels, [{:integer, minimum: 1, maximum: 512}], min_items: 1
  field :position, %{x: :integer, y: :integer}, nullable: true
end
```

See [parsing semantics](parsing-semantics.md#type-conversion-and-validation) for accepted string representations and conversion rules for dates and datetimes.

## Field options

| Option | Applies to | Purpose |
| --- | --- | --- |
| `source:` | field | Maps an input key |
| `minimum:` / `maximum:` | `:integer`, `:float`, `:number` | Validates numeric lower and upper bounds |
| `min_length:` / `max_length:` | `:string` | Validates string length |
| `pattern:` / `format:` | `:string` | Validates a JSON Schema pattern or format |
| `min_items:` / `max_items:` / `unique_items:` | list | Validates size and duplicates |
| `enum:` / `in:` | scalar types, except atom enums | Restricts permitted values |
| `nullable:` / `optional:` / `default:` | field | Controls `nil`, absence, and defaults |
| `strict:` | map | Rejects unknown keys in the map |
| `error:` | field or nested value | Sets the reason returned on failure |
| `json_schema:` | all types | Adds JSON Schema, or disables the value with `false` |

Elements in `enum:` and `in:` must use the converted value's type. `in:` accepts a finite list, `Range`, or `MapSet`. See [using `json_schema:`](json-schema-usage.md) for its merge rules and intended use.

## Custom types

A module implementing `ExParamsSchema.Type` can be used as `{Module, options}`. The adapter converts input into a domain value, and `to_json/2` converts it to a JSON-compatible value for JSON Schema validation. A custom type can therefore return an application-friendly value while still using standard field-option constraints.

```text
input → cast/2 → adapter value → validate/2 (optional)
    → to_json/2 → JSON Schema validation → params struct
```

`cast/2` and `validate/2` perform type-specific conversion and validation. Field options such as `minimum:`, `min_length:`, and `pattern:` apply to the value returned by `to_json/2` and the JSON Schema returned by `json_schema/1`. For example, represent an amount as `%{cents: integer()}` and return an integer from `to_json/2` to apply `minimum:` to the amount in cents.

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

### Adapter options and field options

The `options` in `{Module, options}` belong only to the adapter. In the preceding example, `minimum:` and `error:` are field options, so they are outside the tuple. Adapter options are passed unchanged to `cast/2`, `to_json/2`, `json_schema/1`, and `validate/2`.

```elixir
field :price,
  {MyApp.PriceType, currency: :jpy, minimum_cents: 100},
  minimum: 100,
  error: :invalid_price
```

Implement `validate_options/1` when the adapter accepts its own options. It runs when the schema is defined, detecting unknown options and invalid values early instead of at parse time.

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

### Callback contract

| Callback | Required | Return value and purpose |
| --- | --- | --- |
| `cast(input, options)` | Yes | `{:ok, value}` or `{:error, detail}`. Converts external input to the adapter value. |
| `to_json(value, options)` | Yes | A JSON-compatible value used for field options and JSON Schema validation. |
| `json_schema(options)` | Yes | A map of additional JSON Schema, or `false` to always reject. |
| `validate(value, options)` | No | `:ok` or `{:error, detail}`. Applies type-specific constraints after conversion. |
| `validate_options(options)` | No | `:ok` or `{:error, message}`. Validates adapter options while defining the schema. |
| `typespec()` | No | AST representing the field type in the generated params struct. |

When `cast/2` or `validate/2` returns `{:error, detail}`, `detail` is not exposed externally; it is normalized to the field's `error:` (or `{:invalid_param, field_name}` when omitted). To expose a detailed failure reason to callers, set the field's `error:` instead of relying on the adapter's `detail`.

If `typespec/0` is omitted and the adapter is a struct, its `t/0` is referenced. A non-struct adapter becomes `dynamic()`. Implement `typespec/0` to accurately represent primitive values such as strings.

See the `ExParamsSchema.Type` moduledoc for complete callback type definitions. The adapter's `cast/2` decides how to treat surrounding whitespace. See [parsing semantics](parsing-semantics.md#type-conversion-and-validation) for parsing order and differences from built-in types.

## JSON Schema output

`json_schema/0` or `ExParamsSchema.json_schema/1` returns JSON Schema Draft 7 generated from the declaration.

```elixir
iex> ExParamsSchema.json_schema(%{count: {:integer, minimum: 1}})
...> |> get_in(["properties", "count"])
%{"minimum" => 1, "type" => "integer"}
```
