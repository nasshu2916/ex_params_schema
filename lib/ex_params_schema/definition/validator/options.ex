defmodule ExParamsSchema.Definition.Validator.Options do
  @moduledoc false

  alias ExParamsSchema.Definition

  @membership_options [:enum, :in]
  @bound_pairs [{:minimum, :maximum}, {:min_length, :max_length}, {:min_items, :max_items}]

  @type option_context :: :field | :item
  @type option_predicate :: {option_name :: atom(), predicate :: (term() -> boolean())}

  @spec validate!(Keyword.t(), atom(), Definition.definition_path(), option_context()) :: :ok
  def validate!(options, type, path, context) do
    validate_context!(options, context, path)
    validate_values!(options, path)
    validate_constraint_types!(options, type, path)
    validate_membership_values!(options, type, path)

    Enum.each(@bound_pairs, fn {minimum, maximum} ->
      validate_bounds!(options, minimum, maximum, path)
    end)
  end

  @spec validate_context!(Keyword.t(), option_context(), Definition.definition_path()) :: :ok
  defp validate_context!(_options, :field, _path), do: :ok

  defp validate_context!(options, _context, path) do
    case Keyword.keys(options) -- (Definition.Options.known() -- Definition.Options.field_only()) do
      [] -> :ok
      invalid -> raise_definition!(path, "options #{inspect(invalid)} are only valid on fields")
    end
  end

  @spec validate_values!(Keyword.t(), Definition.definition_path()) :: :ok
  defp validate_values!(options, path) do
    Enum.each(Definition.Options.rules(), fn {name, _rule} ->
      validate_option!(options, name, path)
    end)
  end

  @spec validate_option!(Keyword.t(), atom(), Definition.definition_path()) :: :ok
  defp validate_option!(options, name, path) do
    case Keyword.fetch(options, name) do
      {:ok, value} ->
        unless Definition.Options.valid_value?(name, value) do
          raise_definition!(path, "invalid #{name}: #{inspect(value)}")
        end

      :error ->
        :ok
    end
  end

  @spec validate_constraint_types!(Keyword.t(), atom(), Definition.definition_path()) :: :ok
  defp validate_constraint_types!(options, type, path) do
    Enum.each(Definition.Options.rules(), fn {name, rule} ->
      validate_allowed_type!(options, name, rule, type, path)
    end)
  end

  @spec validate_membership_values!(Keyword.t(), atom(), Definition.definition_path()) :: :ok
  defp validate_membership_values!(_options, :custom, _path), do: :ok

  defp validate_membership_values!(options, type, path) do
    Enum.each(@membership_options, &validate_membership_value!(options, &1, type, path))
  end

  @spec validate_membership_value!(Keyword.t(), :enum | :in, atom(), Definition.definition_path()) :: :ok
  defp validate_membership_value!(options, option, type, path) do
    case Keyword.fetch(options, option) do
      {:ok, values} ->
        unless Enum.all?(membership_values(values), &type_compatible?(&1, type, options)),
          do: raise_definition!(path, "invalid #{option}: values must be compatible with #{inspect(type)}")

      :error ->
        :ok
    end
  end

  @spec membership_values(Enumerable.t()) :: [term()]
  defp membership_values(values) when is_list(values), do: values
  defp membership_values(values), do: Enum.to_list(values)

  @spec type_compatible?(term(), atom(), Keyword.t()) :: boolean()
  defp type_compatible?(nil, :null, _options), do: true
  defp type_compatible?(nil, _type, options), do: Keyword.get(options, :nullable, false)
  defp type_compatible?(_value, :any, _options), do: true
  defp type_compatible?(value, :boolean, _options), do: is_boolean(value)
  defp type_compatible?(value, :float, _options), do: is_float(value)
  defp type_compatible?(value, :integer, _options), do: is_integer(value)
  defp type_compatible?(value, :number, _options), do: is_number(value)
  defp type_compatible?(value, :string, _options), do: is_binary(value)

  @spec validate_allowed_type!(Keyword.t(), atom(), Definition.Options.rule(), atom(), Definition.definition_path()) ::
          :ok
  defp validate_allowed_type!(options, name, _rule, type, path) do
    if Keyword.has_key?(options, name) and not Definition.Options.allowed_for_type?(name, type) do
      raise_definition!(path, "options #{inspect([name])} cannot be used with #{inspect(type)}")
    end

    :ok
  end

  @spec validate_bounds!(Keyword.t(), atom(), atom(), Definition.definition_path()) :: :ok
  defp validate_bounds!(options, minimum, maximum, path) do
    with {:ok, lower} <- Keyword.fetch(options, minimum),
         {:ok, upper} <- Keyword.fetch(options, maximum),
         true <- lower > upper do
      raise_definition!(path, "#{minimum} must be less than or equal to #{maximum}")
    else
      _other -> :ok
    end
  end

  @spec raise_definition!(Definition.definition_path(), String.t()) :: no_return()
  defp raise_definition!(path, message) do
    location = if path == [], do: "root", else: Enum.join(path, ".")
    raise ArgumentError, "invalid schema at #{location}: #{message}"
  end
end
