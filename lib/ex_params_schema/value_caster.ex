defmodule ExParamsSchema.ValueCaster do
  @moduledoc """
  Recursively casts scalar values, arrays, and objects according to normalized type definitions.

  This low-level module is shared by `ExParamsSchema.Parser` and default-value compilation.
  Use `ExParamsSchema.parse/2` for normal input casting.
  """

  alias ExParamsSchema.Caster
  alias ExParamsSchema.Definition.Field

  @type cast_error_path :: [ExParamsSchema.ValidationError.path_segment()]
  @type detailed_cast_result ::
          {:ok, ExParamsSchema.value()}
          | {:error,
             {path :: cast_error_path(), reason :: ExParamsSchema.error_reason()}
             | ExParamsSchema.ValidationError.t()}
  @type field_cast_result ::
          {:ok, name :: atom(), value :: ExParamsSchema.value()}
          | {:error,
             {path :: cast_error_path(), reason :: ExParamsSchema.error_reason()}
             | ExParamsSchema.ValidationError.t()}

  @type collected_field_cast_result ::
          {:ok, name :: atom(), value :: ExParamsSchema.value()}
          | {:error, [ExParamsSchema.ValidationError.t()]}

  @type collected_detailed_cast_result ::
          {:ok, ExParamsSchema.value()} | {:error, [ExParamsSchema.ValidationError.t()]}

  @doc """
  Casts a value to a normalized type.

      iex> ExParamsSchema.ValueCaster.cast(["1", 2], {:array, :integer, []}, [], :invalid_items)
      {:ok, [1, 2]}

      iex> fields = ExParamsSchema.Definition.compile_fields!([{:count, :integer, []}])
      iex> ExParamsSchema.ValueCaster.cast(%{"count" => "3"}, {:object, fields}, [], :invalid_payload)
      {:ok, %{count: 3}}

  Returns `nil` unchanged when `nullable: true`. Values that cannot be cast are normalized to the
  supplied error reason.

      iex> ExParamsSchema.ValueCaster.cast(nil, :integer, [nullable: true], :invalid_count)
      {:ok, nil}
      iex> ExParamsSchema.ValueCaster.cast("x", :integer, [], :invalid_count)
      {:error, :invalid_count}
  """
  @spec cast(
          ExParamsSchema.value(),
          Field.normalized_type(),
          ExParamsSchema.field_options(),
          ExParamsSchema.error_reason()
        ) :: Caster.cast_result()
  def cast(value, type, options, reason) do
    case cast_detailed(value, type, options, reason) do
      {:ok, casted} -> {:ok, casted}
      {:error, {_path, error_reason}} -> {:error, error_reason}
      {:error, %ExParamsSchema.ValidationError{reason: error_reason}} -> {:error, error_reason}
    end
  end

  @doc false
  @spec cast_detailed(
          ExParamsSchema.value(),
          Field.normalized_type(),
          ExParamsSchema.field_options(),
          ExParamsSchema.error_reason()
        ) :: detailed_cast_result()
  def cast_detailed(nil, :null, _options, _reason), do: {:ok, nil}

  def cast_detailed(nil, _type, options, reason) do
    if Keyword.get(options, :nullable, false), do: {:ok, nil}, else: cast_error(reason)
  end

  def cast_detailed(value, {:object, fields}, options, reason) when is_map(value) do
    cast_object(value, fields, options, reason)
  end

  def cast_detailed(value, {:array, item_type, item_options}, _options, reason) when is_list(value) do
    cast_array(value, item_type, item_options, reason)
  end

  def cast_detailed(value, type, _options, reason) do
    case Caster.cast(value, type, reason) do
      {:ok, casted} -> {:ok, casted}
      {:error, error_reason} -> cast_error(error_reason)
    end
  end

  @doc false
  @spec cast_field(map(), Field.t(), ExParamsSchema.error_reason() | nil) :: field_cast_result()
  def cast_field(params, %Field{} = field, inherited_reason \\ nil) do
    reason = Field.error_reason(field, inherited_reason)

    case Field.fetch_value(params, field) do
      {:ok, value} -> cast_present_field(value, field, reason)
      :error -> cast_missing_field(field, reason)
    end
  end

  @doc false
  @spec cast_fields(map(), [Field.t()], ExParamsSchema.error_reason() | nil) :: detailed_cast_result()
  def cast_fields(params, fields, inherited_reason \\ nil) do
    Enum.reduce_while(fields, {:ok, %{}}, fn %Field{} = field, {:ok, parsed} ->
      case cast_field(params, field, inherited_reason) do
        {:ok, name, value} -> {:cont, {:ok, Map.put(parsed, name, value)}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  @doc false
  @spec cast_fields_detailed(map(), [Field.t()], ExParamsSchema.error_reason() | nil) ::
          {:ok, map()} | {:error, [ExParamsSchema.ValidationError.t()]}
  def cast_fields_detailed(params, fields, inherited_reason \\ nil) do
    {parsed, errors} =
      Enum.reduce(fields, {%{}, []}, fn %Field{} = field, {parsed, errors} ->
        case cast_field_detailed(params, field, inherited_reason) do
          {:ok, name, value} -> {Map.put(parsed, name, value), errors}
          {:error, field_errors} -> {parsed, errors ++ field_errors}
        end
      end)

    if errors == [], do: {:ok, parsed}, else: {:error, errors}
  end

  @spec cast_array(
          [ExParamsSchema.value()],
          Field.normalized_type(),
          ExParamsSchema.field_options(),
          ExParamsSchema.error_reason()
        ) :: detailed_cast_result()
  defp cast_array(values, type, options, reason) do
    item_reason = Keyword.get(options, :error, reason)

    values
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {value, index}, {:ok, casted} ->
      case cast_detailed(value, type, options, item_reason) do
        {:ok, value} ->
          {:cont, {:ok, [value | casted]}}

        {:error, {path, error_reason}} ->
          {:halt, {:error, {[index | path], error_reason}}}

        {:error, %ExParamsSchema.ValidationError{} = error} ->
          {:halt, {:error, prefix_error_path(error, index)}}
      end
    end)
    |> reverse_values()
  end

  @spec cast_object(map(), [Field.t()], ExParamsSchema.field_options(), ExParamsSchema.error_reason()) ::
          detailed_cast_result()
  defp cast_object(value, fields, options, reason) do
    with :ok <- reject_unknown_fields(value, fields, Keyword.get(options, :strict, false), reason),
         {:ok, parsed} <- cast_fields(value, fields, reason) do
      {:ok, parsed}
    end
  end

  @spec cast_detailed_all(
          ExParamsSchema.value(),
          Field.normalized_type(),
          ExParamsSchema.field_options(),
          ExParamsSchema.error_reason()
        ) :: collected_detailed_cast_result()
  defp cast_detailed_all(nil, :null, _options, _reason), do: {:ok, nil}

  defp cast_detailed_all(nil, _type, options, reason) do
    if Keyword.get(options, :nullable, false), do: {:ok, nil}, else: {:error, [cast_error_value(reason)]}
  end

  defp cast_detailed_all(value, {:object, fields}, options, reason) when is_map(value) do
    cast_object_detailed(value, fields, options, reason)
  end

  defp cast_detailed_all(value, {:array, item_type, item_options}, _options, reason) when is_list(value) do
    cast_array_detailed(value, item_type, item_options, reason)
  end

  defp cast_detailed_all(value, type, _options, reason) do
    case Caster.cast(value, type, reason) do
      {:ok, casted} -> {:ok, casted}
      {:error, error_reason} -> {:error, [cast_error_value(error_reason)]}
    end
  end

  @spec cast_field_detailed(map(), Field.t(), ExParamsSchema.error_reason() | nil) ::
          collected_field_cast_result()
  defp cast_field_detailed(params, %Field{} = field, inherited_reason) do
    reason = Field.error_reason(field, inherited_reason)

    case Field.fetch_value(params, field) do
      {:ok, value} ->
        if Field.optional_empty?(field, value) do
          {:ok, field.name, nil}
        else
          cast_field_value_detailed(value, field, reason)
        end

      :error ->
        cast_missing_field_detailed(field, reason)
    end
  end

  @spec cast_field_value_detailed(ExParamsSchema.value(), Field.t(), ExParamsSchema.error_reason()) ::
          collected_field_cast_result()
  defp cast_field_value_detailed(value, %Field{} = field, reason) do
    case cast_detailed_all(value, field.type, field.options, reason) do
      {:ok, casted} -> {:ok, field.name, casted}
      {:error, errors} -> {:error, Enum.map(errors, &prefix_error_path(&1, Atom.to_string(field.name)))}
    end
  end

  @spec cast_missing_field_detailed(Field.t(), ExParamsSchema.error_reason()) :: collected_field_cast_result()
  defp cast_missing_field_detailed(field, reason) do
    case Field.missing_value(field) do
      {:default, value} -> cast_field_value_detailed(value, field, reason)
      :optional -> {:ok, field.name, nil}
      :required -> {:error, [cast_error_value(reason)] |> prefix_errors(Atom.to_string(field.name))}
    end
  end

  @spec cast_array_detailed(
          [ExParamsSchema.value()],
          Field.normalized_type(),
          ExParamsSchema.field_options(),
          ExParamsSchema.error_reason()
        ) :: collected_detailed_cast_result()
  defp cast_array_detailed(values, type, options, reason) do
    item_reason = Keyword.get(options, :error, reason)

    {casted, errors} =
      values
      |> Enum.with_index()
      |> Enum.reduce({[], []}, fn {value, index}, {casted, errors} ->
        case cast_detailed_all(value, type, options, item_reason) do
          {:ok, value} -> {[value | casted], errors}
          {:error, item_errors} -> {casted, errors ++ prefix_errors(item_errors, index)}
        end
      end)

    if errors == [], do: {:ok, Enum.reverse(casted)}, else: {:error, errors}
  end

  @spec cast_object_detailed(map(), [Field.t()], ExParamsSchema.field_options(), ExParamsSchema.error_reason()) ::
          collected_detailed_cast_result()
  defp cast_object_detailed(value, fields, options, reason) do
    unknown_errors = unknown_field_errors(value, fields, Keyword.get(options, :strict, false), reason)

    case cast_fields_detailed(value, fields, reason) do
      {:ok, parsed} when unknown_errors == [] -> {:ok, parsed}
      {:ok, _parsed} -> {:error, unknown_errors}
      {:error, errors} -> {:error, unknown_errors ++ errors}
    end
  end

  @spec cast_present_field(ExParamsSchema.value(), Field.t(), ExParamsSchema.error_reason()) ::
          field_cast_result()
  defp cast_present_field(value, %Field{} = field, reason) do
    if Field.optional_empty?(field, value) do
      {:ok, field.name, nil}
    else
      cast_field_value(value, field, reason)
    end
  end

  @spec cast_field_value(ExParamsSchema.value(), Field.t(), ExParamsSchema.error_reason()) ::
          field_cast_result()
  defp cast_field_value(value, %Field{} = field, reason) do
    case cast_detailed(value, field.type, field.options, reason) do
      {:ok, casted} ->
        {:ok, field.name, casted}

      {:error, {path, error_reason}} ->
        {:error, {[Atom.to_string(field.name) | path], error_reason}}

      {:error, %ExParamsSchema.ValidationError{} = error} ->
        {:error, prefix_error_path(error, Atom.to_string(field.name))}
    end
  end

  @spec cast_missing_field(Field.t(), ExParamsSchema.error_reason()) :: field_cast_result()
  defp cast_missing_field(field, reason) do
    case Field.missing_value(field) do
      {:default, value} -> cast_field_value(value, field, reason)
      :optional -> {:ok, field.name, nil}
      :required -> {:error, {[Atom.to_string(field.name)], reason}}
    end
  end

  @spec reject_unknown_fields(map(), [Field.t()], boolean(), ExParamsSchema.error_reason()) ::
          :ok | {:error, {cast_error_path(), ExParamsSchema.error_reason()}}
  defp reject_unknown_fields(_params, _fields, false, _reason), do: :ok

  defp reject_unknown_fields(params, fields, true, reason) do
    case Field.unknown_input_key(params, fields) do
      nil -> :ok
      key -> {:error, unknown_field_error(key, reason)}
    end
  end

  @spec unknown_field_error(term(), ExParamsSchema.error_reason()) :: ExParamsSchema.ValidationError.t()
  defp unknown_field_error(key, reason) do
    %ExParamsSchema.ValidationError{
      path: [unknown_field_path(key)],
      keyword: :additional_properties,
      reason: reason,
      details: %{key: key}
    }
  end

  @spec unknown_field_errors(map(), [Field.t()], boolean(), ExParamsSchema.error_reason()) :: [
          ExParamsSchema.ValidationError.t()
        ]
  defp unknown_field_errors(_params, _fields, false, _reason), do: []

  defp unknown_field_errors(params, fields, true, reason) do
    allowed_keys =
      fields
      |> Enum.flat_map(fn field -> [Field.input_key(field), field.name] end)
      |> MapSet.new()

    params
    |> Map.keys()
    |> Enum.reject(&MapSet.member?(allowed_keys, &1))
    |> Enum.sort_by(&unknown_field_path/1)
    |> Enum.map(&unknown_field_error(&1, reason))
  end

  defp unknown_field_path(key) when is_binary(key), do: key
  defp unknown_field_path(key) when is_atom(key), do: Atom.to_string(key)
  defp unknown_field_path(key), do: inspect(key)

  @spec prefix_error_path(ExParamsSchema.ValidationError.t(), term()) :: ExParamsSchema.ValidationError.t()
  defp prefix_error_path(%ExParamsSchema.ValidationError{} = error, segment) do
    %{error | path: [segment | error.path]}
  end

  @spec prefix_errors([ExParamsSchema.ValidationError.t()], term()) :: [ExParamsSchema.ValidationError.t()]
  defp prefix_errors(errors, segment), do: Enum.map(errors, &prefix_error_path(&1, segment))

  @spec cast_error_value(ExParamsSchema.error_reason()) :: ExParamsSchema.ValidationError.t()
  defp cast_error_value(reason), do: %ExParamsSchema.ValidationError{path: [], keyword: :cast, reason: reason}

  @spec cast_error(ExParamsSchema.error_reason()) ::
          {:error, {cast_error_path(), ExParamsSchema.error_reason()}}
  defp cast_error(reason), do: {:error, {[], reason}}

  @spec reverse_values(detailed_cast_result()) :: detailed_cast_result()
  defp reverse_values({:ok, values}), do: {:ok, Enum.reverse(values)}
  defp reverse_values({:error, _reason} = error), do: error
end
