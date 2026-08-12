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

  `to_form_errors/1` は同じ `path` の `reason` をまとめ、フォームで表示しやすい map に変換します。

      iex> errors = [
      ...>   %ExParamsSchema.ValidationError{path: ["email"], keyword: :format, reason: :invalid_email},
      ...>   %ExParamsSchema.ValidationError{path: ["email"], keyword: :min_length, reason: :invalid_email}
      ...> ]
      iex> ExParamsSchema.ValidationError.to_form_errors(errors)
      %{["email"] => [:invalid_email, :invalid_email]}
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

  @doc """
  詳細検証エラーを、パスごとに `reason` をまとめたフォーム表示用の map に変換します。

  `path` はそのまま map のキーになるため、ネストした object や array のエラーも区別されます。
  各 `reason` の順序は入力のエラー list の順序を保ちます。
  """
  @spec to_form_errors([t()]) :: %{required([path_segment()]) => [ExParamsSchema.error_reason()]}
  def to_form_errors(errors) do
    Enum.group_by(errors, & &1.path, & &1.reason)
  end
end
