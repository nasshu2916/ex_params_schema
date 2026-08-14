defmodule ExParamsSchema.JsonSchema.ModuleGenerator do
  @moduledoc false

  @supported_types %{
    "boolean" => :boolean,
    "integer" => :integer,
    "number" => :number,
    "string" => :string,
    "null" => :null
  }
  @draft7 "http://json-schema.org/draft-07/schema#"

  @doc """
  Produces a `defschema` module source from a JSON Schema Draft 7 object schema.

  Constraints without a direct DSL option remain in `json_schema:` so that the
  generated module continues to validate them.
  """
  @spec generate!(map(), String.t()) :: String.t()
  def generate!(schema, module_name) when is_map(schema) and is_binary(module_name) do
    validate_schema_version!(schema)
    module = module_name!(module_name)
    properties = fetch_properties!(schema)
    required = schema |> Map.get("required", []) |> required_keys!()
    strict = Map.get(schema, "additionalProperties") == false

    fields =
      properties
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(&field_ast(&1, required))

    module
    |> module_ast(strict, fields)
    |> Macro.to_string()
    |> Code.format_string!()
    |> IO.iodata_to_binary()
  end

  def generate!(_schema, _module_name), do: raise(ArgumentError, "JSON Schema must be an object")

  defp validate_schema_version!(schema) do
    case Map.get(schema, "$schema") do
      nil ->
        :ok

      @draft7 ->
        :ok

      version when is_binary(version) ->
        raise ArgumentError, "unsupported JSON Schema version #{inspect(version)}; only Draft 7 is supported"

      version ->
        raise ArgumentError, "JSON Schema $schema must be a string, got: #{inspect(version)}"
    end
  end

  defp module_ast(module, strict, fields) do
    quote do
      defmodule unquote(module) do
        use ExParamsSchema

        defschema strict: unquote(strict) do
          (unquote_splicing(fields))
        end
      end
    end
  end

  defp field_ast({name, schema}, required) when is_binary(name) and is_map(schema) do
    {type, options} = definition(schema, MapSet.member?(required, name))

    if options == [] do
      quote do
        field unquote(String.to_atom(name)), unquote(Macro.escape(type))
      end
    else
      quote do
        field unquote(String.to_atom(name)), unquote(Macro.escape(type)), unquote(Macro.escape(options))
      end
    end
  end

  defp field_ast({name, _schema}, _required),
    do: raise(ArgumentError, "property #{inspect(name)} must be an object schema")

  defp definition(schema, required?) do
    {type, nullable?} = type_for(schema)

    options =
      []
      |> maybe_put(:optional, not required?)
      |> maybe_put(:nullable, nullable?)
      |> maybe_put(:default, Map.fetch(schema, "default"))
      |> maybe_put(:strict, is_map(type) and Map.get(schema, "additionalProperties") == false)
      |> maybe_put(:json_schema, remaining_schema(schema, type))

    {type, options}
  end

  defp type_for(%{"type" => types} = schema) when is_list(types) do
    nullable? = "null" in types

    case types -- ["null"] do
      [type] -> {type_for_type(type, schema), nullable?}
      _ -> {:any, false}
    end
  end

  defp type_for(%{"type" => type} = schema), do: {type_for_type(type, schema), false}
  defp type_for(%{"properties" => _}), do: {:object, false}
  defp type_for(_schema), do: {:any, false}

  defp type_for_type("object", schema) do
    case Map.get(schema, "properties") do
      properties when is_map(properties) ->
        required = schema |> Map.get("required", []) |> required_keys!()

        Map.new(properties, fn {name, child_schema} ->
          {String.to_atom(name), definition(child_schema, MapSet.member?(required, name))}
        end)

      _ ->
        :any
    end
  end

  defp type_for_type("array", %{"items" => item_schema}) when is_map(item_schema) do
    {item_type, item_options} = definition(item_schema, true)
    [{item_type, Keyword.delete(item_options, :optional)}]
  end

  defp type_for_type(type, _schema), do: Map.get(@supported_types, type, :any)

  defp remaining_schema(schema, type) do
    schema
    |> Map.delete("default")
    |> drop_represented_type(type)
    |> drop_represented_object_keys(type)
    |> drop_represented_array_keys(type)
    |> empty_to_nil()
  end

  defp drop_represented_type(schema, :any), do: schema
  defp drop_represented_type(schema, _type), do: Map.delete(schema, "type")

  defp drop_represented_object_keys(schema, type) when is_map(type) do
    schema = Map.drop(schema, ["properties", "required"])
    if Map.get(schema, "additionalProperties") == false, do: Map.delete(schema, "additionalProperties"), else: schema
  end

  defp drop_represented_object_keys(schema, _type), do: schema

  defp drop_represented_array_keys(schema, [_]), do: Map.delete(schema, "items")
  defp drop_represented_array_keys(schema, _type), do: schema

  defp empty_to_nil(schema) when map_size(schema) == 0, do: nil
  defp empty_to_nil(schema), do: schema

  defp maybe_put(options, _key, false), do: options
  defp maybe_put(options, _key, nil), do: options
  defp maybe_put(options, _key, :error), do: options
  defp maybe_put(options, key, {:ok, value}), do: Keyword.put(options, key, value)
  defp maybe_put(options, key, value), do: Keyword.put(options, key, value)

  defp fetch_properties!(%{"properties" => properties}) when is_map(properties), do: properties
  defp fetch_properties!(_schema), do: raise(ArgumentError, "JSON Schema root must contain an object properties map")

  defp required_keys!(required) when is_list(required) do
    if Enum.all?(required, &is_binary/1) do
      MapSet.new(required)
    else
      raise ArgumentError, "JSON Schema required must be an array of strings"
    end
  end

  defp required_keys!(_required), do: raise(ArgumentError, "JSON Schema required must be an array of strings")

  defp module_name!(module_name) do
    if Regex.match?(~r/^[A-Z][A-Za-z0-9_]*(\.[A-Z][A-Za-z0-9_]*)*$/, module_name) do
      module_name |> String.split(".") |> Module.concat()
    else
      raise ArgumentError, "MODULE must be an Elixir module name, got: #{inspect(module_name)}"
    end
  end
end
