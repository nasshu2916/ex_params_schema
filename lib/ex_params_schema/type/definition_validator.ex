defmodule ExParamsSchema.Type.DefinitionValidator do
  @moduledoc false

  @required_callbacks [cast: 2, to_json: 2, json_schema: 1]

  @spec validate_definition!(module(), keyword(), ExParamsSchema.Definition.definition_path()) :: :ok
  def validate_definition!(module, options, path) when is_atom(module) and is_list(options) do
    ensure_adapter!(module, path)
    validate_options!(module, options, path)
    validate_json_schema!(module, options, path)
  end

  def validate_definition!(module, _options, path) do
    raise_invalid!(path, "custom type module must be an atom, got: #{inspect(module)}")
  end

  @spec ensure_adapter!(module(), ExParamsSchema.Definition.definition_path()) :: :ok
  defp ensure_adapter!(module, path) do
    case Code.ensure_compiled(module) do
      {:module, ^module} -> :ok
      {:error, reason} -> raise_invalid!(path, "could not compile custom type #{inspect(module)}: #{inspect(reason)}")
    end

    missing = Enum.reject(@required_callbacks, fn {name, arity} -> function_exported?(module, name, arity) end)
    if missing != [], do: raise_invalid!(path, "custom type #{inspect(module)} must implement #{inspect(missing)}")

    :ok
  end

  @spec validate_options!(module(), keyword(), ExParamsSchema.Definition.definition_path()) :: :ok
  defp validate_options!(module, options, path) do
    case optional_result(module, :validate_options, [options]) do
      :ok -> :ok
      {:error, message} when is_binary(message) -> raise_invalid!(path, message)
      {:error, detail} -> raise_invalid!(path, "invalid validate_options/1 result: #{inspect({:error, detail})}")
      {:invalid, other} -> raise_invalid!(path, "invalid validate_options/1 result: #{inspect(other)}")
    end
  end

  @spec validate_json_schema!(module(), keyword(), ExParamsSchema.Definition.definition_path()) :: :ok
  defp validate_json_schema!(module, options, path) do
    case module.json_schema(options) do
      schema when is_map(schema) or is_boolean(schema) -> :ok
      other -> raise_invalid!(path, "json_schema/1 must return a map or boolean, got: #{inspect(other)}")
    end
  end

  @spec optional_result(module(), atom(), [term()]) :: :ok | {:error, term()} | {:invalid, term()}
  defp optional_result(module, name, arguments) do
    result = if function_exported?(module, name, length(arguments)), do: apply(module, name, arguments), else: :ok
    if result == :ok or match?({:error, _}, result), do: result, else: {:invalid, result}
  end

  @spec raise_invalid!(ExParamsSchema.Definition.definition_path(), String.t()) :: no_return()
  defp raise_invalid!(path, message), do: raise(ArgumentError, "invalid schema at #{Enum.join(path, ".")}: #{message}")
end
