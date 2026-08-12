defmodule ExParamsSchema.Schema.Projector do
  @moduledoc """
  Converts cast values into JSON-compatible values for JSON Schema validation.

  It handles dates, datetimes, enums, custom types, and nested objects and arrays.
  """

  alias ExParamsSchema.Definition.Field

  @doc """
  Converts validated field values into a JSON-compatible map.

  Omits `nil` values for optional fields from the output.

      iex> fields = ExParamsSchema.Definition.compile_fields!([
      ...>   {:published_on, :date, []},
      ...>   {:label, :string, [optional: true]}
      ...> ])
      iex> ExParamsSchema.Schema.Projector.project(fields, %{published_on: ~D[2026-07-23], label: nil})
      %{"published_on" => "2026-07-23"}
  """
  @spec project([Field.t()], map()) :: map()
  def project(fields, parsed) do
    Enum.reduce(fields, %{}, fn %Field{} = field, projected ->
      name = field.name
      value = Map.fetch!(parsed, name)

      if Field.omit_from_validation?(field, value) do
        projected
      else
        Map.put(projected, Atom.to_string(name), project_value(field.type, value))
      end
    end)
  end

  @doc """
  Converts a single value into a JSON-compatible value based on its type.

      iex> ExParamsSchema.Schema.Projector.project_value({:array, :date, []}, [~D[2026-07-22]])
      ["2026-07-22"]
  """
  @spec project_value(Field.normalized_type(), ExParamsSchema.value()) :: ExParamsSchema.value()
  def project_value(_type, nil), do: nil
  def project_value({:enum, _allowed}, value), do: Atom.to_string(value)

  def project_value({:custom, module, options}, value),
    do: ExParamsSchema.Type.to_json(module, value, options)

  def project_value(:date, value), do: Date.to_iso8601(value)
  def project_value(:datetime, value), do: DateTime.to_iso8601(value)

  def project_value({:array, type, _options}, value) do
    Enum.map(value, &project_value(type, &1))
  end

  def project_value({:object, fields}, value), do: project(fields, value)
  def project_value(_type, value), do: value
end
