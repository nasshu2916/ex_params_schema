defmodule ExParamsSchema.Schema.ErrorPath do
  @moduledoc """
  Maps JSON Schema error paths to schema error definitions.

  This internal module combines JSON Pointer decoding and selection of the most specific error
  definition.
  """

  alias ExParamsSchema.Schema.JsonPointer

  @doc """
  JSON Pointer に対応する宣言順、エラー理由、解決後のパスを返します。

  一致する定義が複数ある場合は、最も具体的なパスを選択します。
  """
  @spec resolve([ExParamsSchema.Schema.error_definition()], String.t()) ::
          ExParamsSchema.Schema.resolved_error_path() | nil
  def resolve(error_definitions, pointer) do
    case JsonPointer.decode(pointer) do
      {:ok, path} ->
        error_definitions
        |> Enum.flat_map(&match_definition(&1, path))
        |> Enum.max_by(fn {specificity, _resolved} -> specificity end, fn -> nil end)
        |> case do
          {_specificity, resolved} -> resolved
          nil -> nil
        end

      :error ->
        nil
    end
  end

  @spec match_definition(
          ExParamsSchema.Schema.error_definition(),
          JsonPointer.pointer_path()
        ) :: [{non_neg_integer(), ExParamsSchema.Schema.resolved_error_path()}]
  defp match_definition({pattern, reason, order}, path) do
    case JsonPointer.match(pattern, path) do
      {:ok, resolved_path} -> [{length(pattern), {order, reason, resolved_path}}]
      :error -> []
    end
  end
end
