defmodule ExParamsSchema.Schema.Options do
  @moduledoc """
  Manages default values and normalization rules for schema-level options.

  This internal module is shared by `use ExParamsSchema`, `defschema`, and map-form schema
  definitions.
  """

  @option_defaults %{strict: false}
  @allowed_option_names Map.keys(@option_defaults)

  defstruct Map.to_list(@option_defaults)

  @type t :: %__MODULE__{strict: boolean()}

  @doc """
  Validates options and normalizes them to the internal representation with defaults applied.

      iex> ExParamsSchema.Schema.Options.normalize!([strict: true], "schema")
      %ExParamsSchema.Schema.Options{strict: true}

      iex> ExParamsSchema.Schema.Options.normalize!(
      ...>   [],
      ...>   "schema",
      ...>   %ExParamsSchema.Schema.Options{strict: true}
      ...> )
      %ExParamsSchema.Schema.Options{strict: true}
  """
  @spec normalize!(keyword(), String.t(), t()) :: t()
  def normalize!(options, function_name, defaults \\ %__MODULE__{}) do
    validate_option_names!(options, function_name)
    strict = Keyword.get(options, :strict, defaults.strict)

    unless is_boolean(strict) do
      raise ArgumentError, "#{function_name} :strict must be a boolean"
    end

    %__MODULE__{strict: strict}
  end

  @spec validate_option_names!(keyword(), String.t()) :: nil
  defp validate_option_names!(options, function_name) do
    unless Keyword.keyword?(options) and Keyword.keys(options) -- @allowed_option_names == [] do
      allowed_key_text = Enum.map_join(@allowed_option_names, ", ", &inspect/1)

      raise ArgumentError,
            "#{function_name} options cannot contain unknown keys. Allowed keys: #{allowed_key_text}"
    end
  end
end
