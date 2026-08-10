defmodule ExParamsSchema.ValidationError do
  @moduledoc """
  `parse_detailed/1` と `parse_detailed/2` が返す検証エラーです。

  `path` は入力のルートからエラー箇所までのセグメントです。map のキーは文字列、list の
  添字は非負整数で表します。`keyword` は JSON Schema の制約、未知キーの
  `:additional_properties`、または変換時の `:cast` です。
  `reason` は同じフィールドに対して通常の `parse` が返す `error:` の値です。

      iex> error = %ExParamsSchema.ValidationError{
      ...>   path: ["entries", 0, "name"],
      ...>   keyword: :min_length,
      ...>   reason: :invalid_name,
      ...>   details: %{expected: 1}
      ...> }
      iex> {error.path, error.keyword, error.reason}
      {["entries", 0, "name"], :min_length, :invalid_name}
  """

  @enforce_keys [:path, :keyword, :reason]
  defstruct [
    :path,
    :keyword,
    :reason,
    details: %{}
  ]

  @type t :: %__MODULE__{
          path: [path_segment()],
          keyword: atom(),
          reason: ExParamsSchema.error_reason(),
          details: map()
        }

  @type path_segment :: String.t() | non_neg_integer()
end
