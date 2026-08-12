defmodule ExParamsSchema.Caster do
  @moduledoc """
  Casts input values to the DSL's built-in types.

  It is used internally by the parser. Use `ExParamsSchema.parse/2` unless you need direct
  access to individual type casts.
  """

  @type cast_result ::
          {:ok, value :: ExParamsSchema.value()} | {:error, reason :: ExParamsSchema.error_reason()}

  @doc """
  入力値を DSL の組み込み型へ変換します。

      iex> ExParamsSchema.Caster.cast("12", :integer, :invalid_count)
      {:ok, 12}

      iex> ExParamsSchema.Caster.cast("12px", :integer, :invalid_count)
      {:error, :invalid_count}

      iex> ExParamsSchema.Caster.cast("1e3", :number, :invalid_number)
      {:ok, 1000.0}

      iex> ExParamsSchema.Caster.cast("on", :boolean, :invalid_enabled)
      {:ok, true}

      iex> ExParamsSchema.Caster.cast("  Front  ", :string, :invalid_label)
      {:ok, "Front"}

      iex> ExParamsSchema.Caster.cast("2026-07-23", :date, :invalid_date)
      {:ok, ~D[2026-07-23]}

      iex> ExParamsSchema.Caster.cast("merge", {:enum, [:merge, :replace]}, :invalid_mode)
      {:ok, :merge}

  変換できない値は、呼び出し側から渡された `reason` をエラーとして返します。
  """
  @spec cast(ExParamsSchema.value(), ExParamsSchema.field_type(), ExParamsSchema.error_reason()) ::
          cast_result()
  def cast(value, :any, _reason), do: {:ok, value}
  def cast(value, :integer, _reason) when is_integer(value), do: {:ok, value}

  def cast(value, :integer, reason) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> {:ok, integer}
      _invalid -> {:error, reason}
    end
  end

  def cast(value, :float, _reason) when is_float(value), do: {:ok, value}
  def cast(value, :float, _reason) when is_integer(value), do: {:ok, value / 1}

  def cast(value, :float, reason) when is_binary(value) do
    case Float.parse(value) do
      {float, ""} -> {:ok, float}
      _invalid -> {:error, reason}
    end
  end

  def cast(value, :number, _reason) when is_number(value), do: {:ok, value}

  def cast(value, :number, reason) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> {:ok, integer}
      _invalid -> cast(value, :float, reason)
    end
  end

  def cast(value, :boolean, _reason) when is_boolean(value), do: {:ok, value}
  def cast(value, :boolean, _reason) when value in ["true", "on", "1", 1], do: {:ok, true}
  def cast(value, :boolean, _reason) when value in ["false", "off", "0", 0], do: {:ok, false}
  def cast(_value, :boolean, reason), do: {:error, reason}

  def cast(value, :string, _reason) when is_binary(value), do: {:ok, String.trim(value)}

  def cast(%Date{} = value, :date, _reason), do: {:ok, value}

  def cast(value, :date, reason) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      {:error, _reason} -> {:error, reason}
    end
  end

  def cast(%DateTime{} = value, :datetime, reason) do
    value
    |> DateTime.to_iso8601()
    |> cast(:datetime, reason)
  end

  def cast(value, :datetime, reason) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _utc_offset} -> {:ok, datetime}
      {:error, _reason} -> {:error, reason}
    end
  end

  def cast(nil, :null, _reason), do: {:ok, nil}

  def cast(value, {:enum, allowed}, reason) do
    case Enum.find(allowed, &(value == &1 or value == Atom.to_string(&1))) do
      nil -> {:error, reason}
      parsed -> {:ok, parsed}
    end
  end

  def cast(value, {:custom, module, options}, reason) do
    ExParamsSchema.Type.cast(module, value, options, reason)
  end

  def cast(_value, _type, reason), do: {:error, reason}
end
