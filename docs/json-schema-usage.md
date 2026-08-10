# Using `json_schema:`

`json_schema:` adds JSON Schema Draft 7 validation constraints that cannot be expressed with the DSL alone. The DSL remains responsible for input type conversion, input-key mapping, and struct or map construction; `json_schema:` only extends validation of the converted value.

[日本語版](json-schema-usage_ja.md)

## Basic example

Specify constraints absent from the DSL, such as `multipleOf` or `exclusiveMinimum`, with additional JSON Schema.

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

Here, `"1.5"` is converted to `1.5` and succeeds, while `"1.0"` returns `:invalid_step`. Both `minimum: 0` and the additional JSON Schema constraints are validated.

## Merge order and overrides

Each field's JSON Schema is built in this order:

1. Generate `"type"` from the DSL type.
2. Add DSL standard constraints (`minimum:`, `min_length:`, `items`, `properties`, and so on).
3. Recursively merge the `json_schema:` map.
4. When `nullable: true`, add `"null"` to the final `"type"`.

For the same key, maps are recursively merged; all other values from the additional JSON Schema replace the DSL-generated value. Therefore, adding constraints to `"properties"` or map-form `"items"` preserves the generated type and sibling properties. Arrays such as `"required"`, scalars, and boolean schemas are replaced by the additional value.

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

Additional JSON Schema may also override `"type"`, but it does not change DSL conversion. For example, adding `"type" => "string"` to `:integer` still converts input to an integer first and will usually conflict at validation. When defining a type, `properties`, or `items` in additional JSON Schema, use `:any` as a rule and pass the input through to JSON Schema unchanged.

When `nullable: true` is combined with an additional `"type"`, `"null"` is added after the override. If the type is already an array, its existing types are preserved and `"null"` is added without duplication. `json_schema: false` makes that field a rejecting boolean schema when present, and does not apply `nullable:`. An absent `optional: true` field is outside JSON Schema validation and succeeds. `json_schema: true` uses the DSL-generated schema as-is.

## Responsibilities of the DSL and JSON Schema

| Capability | Responsible layer |
| --- | --- |
| Converting strings to integers, booleans, and atom enums | DSL |
| Input-key mapping with `source:` | DSL |
| `optional:`, `default:`, and struct/map construction | DSL |
| Range, length, array, logical, and `$ref` validation | JSON Schema |
| Selecting the returned `error:` on failure | DSL |

A DSL map outputs only declared child fields and discards unknown keys. Consequently, adding `properties` or `required` to a DSL map through additional JSON Schema does not make conversion retain that input. For arbitrary-shape objects, tuple-form arrays, or strict `additionalProperties` validation, combine `:any` with additional JSON Schema.

Errors within additional JSON Schema are also converted to the nearest field or nested `error:`. Ordinary `parse` returns only the first `reason`. `parse_detailed` returns the validator keyword, path, and all errors as a list of `ExParamsSchema.ValidationError`.

## Draft 7 and `format:`

The root schema's `$schema` is JSON Schema Draft 7. Validation and `$ref` resolution are delegated to `ex_json_schema` (supported range: `~> 0.11.4`). Therefore, results for keywords outside Draft 7 or not implemented by that dependency are not guaranteed. Regression-test constraints that use additional JSON Schema when updating the dependency.

DSL `format:` can be specified only for `:string`. `"format"` within additional JSON Schema is also passed to the validator; its supported validation depends on the `ex_json_schema` version and application configuration. This library does not configure an individual custom format validator for `ExJsonSchema.Schema.resolve/2`. When using a custom format, configure `ex_json_schema` in the application and test expected values.

## Recommendations

- Declare types and standard constraints expressible in the DSL with the DSL.
- Use additional JSON Schema for constraints such as `multipleOf`, `contains`, `anyOf`, `not`, and `additionalProperties`.
- Use `:any` when overriding types, tuple-form `items`, or `required` in a way that conflicts with DSL conversion.
- Use `json_schema: false` only to explicitly prohibit a present input. Do not combine it with `optional: true` when an absent field must also be rejected.
- Test both accepted and rejected values whenever changing additional JSON Schema.
