defmodule ExParamsSchema.ValidationError do
  @moduledoc """
  Represents validation errors returned by `parse_detailed/1` and `parse_detailed/2`.

  `path` contains the segments from the input root to the error location. Map keys are strings,
  and list indexes are non-negative integers. `keyword` is a JSON Schema constraint,
  `:additional_properties` for unknown keys, or `:cast` for casting errors. `reason` is the
  `error:` value returned by regular `parse` for the same field.

      iex> error = %ExParamsSchema.ValidationError{
      ...>   path: ["entries", 0, "name"],
      ...>   keyword: :min_length,
      ...>   reason: :invalid_name,
      ...>   details: %{expected: 1}
      ...> }
      iex> {error.path, error.keyword, error.reason}
      {["entries", 0, "name"], :min_length, :invalid_name}

  `to_form_errors/1` groups `reason` values with the same `path` and converts them into a map
  suitable for displaying in forms.

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
  Converts detailed validation errors into a form-friendly map that groups `reason` values by path.

  Because `path` is used directly as the map key, nested object and array errors remain distinct.
  The order of each `reason` matches its order in the input error list.
  """
  @spec to_form_errors([t()]) :: %{required([path_segment()]) => [ExParamsSchema.error_reason()]}
  def to_form_errors(errors) do
    Enum.group_by(errors, & &1.path, & &1.reason)
  end
end
