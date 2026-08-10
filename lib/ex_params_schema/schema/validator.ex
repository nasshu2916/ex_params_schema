defmodule ExParamsSchema.Schema.Validator do
  @moduledoc """
  JSON Schema による検証結果を ExParamsSchema のエラー形式へ変換します。

  `ExJsonSchema` との統合に関する内部モジュールです。通常は `parse/2` または
  `parse_detailed/2` を使用してください。
  """

  alias ExParamsSchema.{Schema, Schema.JsonPointer}

  @doc """
  JSON 互換のデータを検証し、最初の宣言に対応するエラー理由へ正規化します。

      iex> schema = ExParamsSchema.compile!(%{count: {:integer, minimum: 1, error: :invalid_count}})
      iex> ExParamsSchema.Schema.Validator.validate(schema, %{"count" => 2})
      :ok
      iex> ExParamsSchema.Schema.Validator.validate(schema, %{"count" => 0})
      {:error, :invalid_count}
  """
  @spec validate(Schema.t(), map()) :: :ok | {:error, ExParamsSchema.error_reason()}
  def validate(%Schema{} = schema, data) do
    case validate_schema(schema, data) do
      :ok ->
        :ok

      {:error, errors} ->
        {:error, validation_reason(schema, errors)}
    end
  end

  @doc """
  JSON 互換のデータを検証し、すべてのエラーをパス付きで返します。

      iex> schema = ExParamsSchema.compile!(%{count: {:integer, minimum: 1, error: :invalid_count}})
      iex> {:error, [error]} = ExParamsSchema.Schema.Validator.validate_detailed(schema, %{"count" => 0})
      iex> {error.path, error.keyword, error.reason}
      {["count"], :minimum, :invalid_count}
  """
  @spec validate_detailed(Schema.t(), map()) ::
          :ok | {:error, [ExParamsSchema.ValidationError.t()]}
  def validate_detailed(%Schema{} = schema, data) do
    case validate_schema(schema, data) do
      :ok ->
        :ok

      {:error, errors} ->
        errors
        |> Enum.flat_map(&detailed_errors(schema, &1))
        |> Enum.sort_by(&elem(&1, 1))
        |> Enum.map(&elem(&1, 0))
        |> then(&{:error, &1})
    end
  end

  @spec validation_reason(Schema.t(), [struct()]) :: ExParamsSchema.error_reason()
  defp validation_reason(schema, errors) do
    case Enum.map(errors, &Schema.resolve_error_path(schema, &1.path))
         |> Enum.reject(&is_nil/1) do
      [] -> :invalid_params
      reasons -> reasons |> Enum.min_by(&elem(&1, 0)) |> elem(1)
    end
  end

  @spec validate_schema(Schema.t(), map()) :: :ok | {:error, [struct()]}
  defp validate_schema(%Schema{} = schema, data) do
    ExJsonSchema.Validator.validate(schema.resolved, data, error_formatter: false)
  end

  @spec detailed_errors(Schema.t(), struct()) :: [
          {ExParamsSchema.ValidationError.t(), non_neg_integer() | :infinity}
        ]
  defp detailed_errors(schema, %ExJsonSchema.Validator.Error{
         error: %ExJsonSchema.Validator.Error.Required{missing: missing},
         path: path
       }) do
    Enum.map(missing, fn name -> detailed_error(schema, path <> "/" <> name, :required, %{}) end)
  end

  defp detailed_errors(schema, %ExJsonSchema.Validator.Error{error: error, path: path}) do
    detailed_error(schema, path, error_keyword(error), Map.from_struct(error)) |> List.wrap()
  end

  @spec detailed_error(Schema.t(), String.t(), atom(), map()) ::
          {ExParamsSchema.ValidationError.t(), non_neg_integer() | :infinity}
  defp detailed_error(schema, path, keyword, details) do
    {order, reason, resolved_path} =
      Schema.resolve_error_path(schema, path) ||
        {:infinity, :invalid_params, JsonPointer.parse(path)}

    error = %ExParamsSchema.ValidationError{
      path: resolved_path,
      keyword: keyword,
      reason: reason,
      details: details
    }

    {error, order}
  end

  @spec error_keyword(struct()) :: atom()
  defp error_keyword(error) do
    error.__struct__
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> String.to_atom()
  end
end
