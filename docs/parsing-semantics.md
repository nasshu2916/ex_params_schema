# Parsing semantics

This page describes the input accepted by `parse/1` and `parse/2`, type conversion, validation, and returned errors. See the [DSL reference](dsl.md) for types and field options.

[日本語版](parsing-semantics_ja.md)

## Input keys

Each field's input key is specified by `source:`. It accepts a string or atom and can be used in both `field/3` within a `defschema` block and map definitions.

Input values are resolved in this order:

1. The key specified by `source:`, or the field name as a string when it is omitted
2. The field name as an atom declared by the schema

When both keys exist in the input map, the string key or the key specified by `source:` takes precedence.

Input fields not present in the schema are ignored by default. This accepts auxiliary parameters added by frameworks such as LiveView or HTTP request handling, and unknown values are not retained in the output struct.

`defschema strict: true do ... end` or `compile!/2` with `strict: true` rejects an unknown top-level key as `{:unknown_param, key}`. `use ExParamsSchema, strict: true` sets a module default. `strict: true` on a nested map applies only to that map; an unknown key returns the nearest `error:` (or the parent field's default error). A strict object is also emitted as JSON Schema with `"additionalProperties": false`.

## Absent values, empty strings, and defaults

When a field is absent, it is processed in this order:

1. Use `default:` when present.
2. Use `nil` when `optional: true`.
3. Otherwise return the field's error.

An explicitly supplied `nil` or empty string for an `optional: true` field becomes `nil`. For a `:string` field, a whitespace-only string also becomes `nil`. In these cases the default is not applied. A default is applied only when the field itself is absent.

Defaults are converted and validated when the schema is defined. A params module with an invalid default cannot compile. The normalized default is used both by `parse/1` and `defstruct`.

## `nullable`

`nullable: true` accepts `nil` when the field is present. It is distinct from `optional: true`, which allows the field to be absent.

## Type conversion and validation

Input is converted to its declared type and then validated against the generated JSON Schema.

```text
Input-key resolution
  → absent-value and empty-string processing
  → type conversion
  → JSON Schema validation
  → struct construction
```

`:string` trims leading and trailing whitespace during conversion, and constraints such as `min_length:` apply to the trimmed string. Other built-in types do not trim input strings: `:integer`, `:float`, `:number`, and `:boolean` reject values such as `" 12 "` and `"true "`. Whitespace handling for custom types is decided by the adapter's `cast/2`.

`:date` converts ISO 8601 date strings to `Date`. `:datetime` accepts ISO 8601 datetimes that include a time zone and normalizes them to UTC `DateTime` values. Datetimes without a time zone are rejected. Both types also accept `Date` / `DateTime` values directly, and apply the same conversion rules to `default:`.

## Schema definition errors

The following problems are reported as `ArgumentError` when a schema is defined, rather than while parsing params:

- Unknown or duplicate options
- Duplicate field names at the same nesting level
- Unsupported types
- Constraints that do not apply to the type, such as `minimum:` on a string
- Invalid option value types
- Reversed bounds such as `minimum` and `maximum`
- An empty atom enum or an enum containing non-atoms
- Field-only options such as `optional:` on a list item
- A default that cannot be converted to its declared type or does not satisfy constraints
- `enum:` or `in:` members incompatible with the converted field value's type

`in:` accepts only lists, ranges, and `MapSet`s that can be determined to be finite at compile time. Arbitrary `Enumerable`s and streams are not accepted.

`enum:` and `in:` members are compared with the converted value by JSON Schema, so they must have the target type. `:any` permits any non-`nil` value; `nil` is allowed only by `nullable: true` or `:null`. Atom enums cannot be combined with `enum:` or `in:`.

## Errors

When casting or validation fails, the field's `error:` is returned. When omitted, it is `{:invalid_param, field_name}`.

Nested values use the nearest `error:`. For multiple JSON Schema errors, fields declared in a keyword list are handled in declaration order. Ordering among nested fields declared in a map is not guaranteed.

## Detailed errors

`parse_detailed/1` and `parse_detailed/2` return the same successful value as ordinary `parse`; on failure, they return a list of `ExParamsSchema.ValidationError`. Each error has `path` (string map keys and integer list indices), `keyword`, `reason`, and `details`. `reason` is the same value returned by ordinary `parse` through `error:`.

Every JSON Schema violation is returned when there are multiple violations. Missing required values, type-conversion errors, and strict-mode unknown keys are collected across every field, nested object, and array item. Their `keyword` is `:cast` or `:additional_properties`, respectively. JSON Schema validation is not run when conversion errors exist because a complete typed value is unavailable.
