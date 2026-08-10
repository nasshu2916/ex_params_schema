defmodule ExParamsSchema.Type.Adapter do
  @moduledoc false

  @spec cast(module(), term(), keyword(), term()) :: ExParamsSchema.Type.cast_result()
  def cast(module, value, options, reason) do
    with {:ok, casted} <- normalize_cast_result(module.cast(value, options), reason),
         :ok <- validate(module, casted, options, reason) do
      {:ok, casted}
    end
  end

  @spec json_schema(module(), keyword()) :: map() | boolean()
  def json_schema(module, options), do: module.json_schema(options)

  @spec to_json(module(), term(), keyword()) :: ExParamsSchema.Type.json_value()
  def to_json(module, value, options), do: module.to_json(value, options)

  @spec validate(module(), term(), keyword(), term()) :: :ok | {:error, term()}
  defp validate(module, value, options, reason) do
    case optional_result(optional_callback(module, :validate, [value, options], :ok)) do
      :ok ->
        :ok

      {:error, _detail} ->
        {:error, reason}

      {:invalid, other} ->
        raise ArgumentError, "#{inspect(module)}.validate/2 returned invalid result: #{inspect(other)}"
    end
  end

  @spec normalize_cast_result(term(), term()) :: ExParamsSchema.Type.cast_result()
  defp normalize_cast_result({:ok, value}, _reason), do: {:ok, value}
  defp normalize_cast_result({:error, _detail}, reason), do: {:error, reason}

  defp normalize_cast_result(other, _reason) do
    raise ArgumentError,
          "custom type cast/2 must return {:ok, value} or {:error, detail}, got: #{inspect(other)}"
  end

  @spec optional_result(term()) :: :ok | {:error, term()} | {:invalid, term()}
  defp optional_result(:ok), do: :ok
  defp optional_result({:error, detail}), do: {:error, detail}
  defp optional_result(other), do: {:invalid, other}

  @spec optional_callback(module(), atom(), [term()], term()) :: term()
  defp optional_callback(module, name, arguments, default) do
    if function_exported?(module, name, length(arguments)),
      do: apply(module, name, arguments),
      else: default
  end
end
