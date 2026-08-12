defmodule ExParamsSchema.Parser do
  @moduledoc """
  コンパイル済みスキーマに対するパラメーターの変換・検証を実行します。

  `ExParamsSchema.parse/2` と、`use ExParamsSchema` が生成する `parse/1` の実装を支える
  低水準モジュールです。通常は公開 API を使用してください。
  """

  alias ExParamsSchema.Definition.Field
  alias ExParamsSchema.{Schema, ValueCaster}
  alias ExParamsSchema.Schema.Validator

  @type struct_parse_result ::
          {:ok, params :: struct()} | {:error, reason :: ExParamsSchema.error_reason()}
  @type map_parse_result :: ExParamsSchema.parse_result()
  @type detailed_parse_result :: ExParamsSchema.detailed_parse_result()

  @doc """
  変換結果を指定した構造体へ格納して返します。

  通常は `use ExParamsSchema` により生成される `parse/1` を使用します。
  """
  @spec parse(term(), module(), Schema.t()) :: struct_parse_result()
  def parse(params, module, %Schema{} = schema) do
    with {:ok, parsed} <- parse(params, schema) do
      {:ok, struct(module, parsed)}
    end
  end

  @doc """
  入力 map を変換・検証し、結果を指定した構造体へ格納して返します。

  通常は `use ExParamsSchema` により生成される `parse_detailed/1` を使用します。
  """
  @spec parse_detailed(term(), module(), Schema.t()) ::
          {:ok, struct()} | {:error, [ExParamsSchema.validation_error()]}
  def parse_detailed(params, module, %Schema{} = schema) do
    with {:ok, parsed} <- parse_detailed(params, schema) do
      {:ok, struct(module, parsed)}
    end
  end

  @doc """
  コンパイル済みスキーマを使い、入力 map を変換・検証します。

      iex> schema = ExParamsSchema.compile!(%{count: {:integer, minimum: 1}})
      iex> ExParamsSchema.Parser.parse(%{"count" => "2"}, schema)
      {:ok, %{count: 2}}

      iex> schema = ExParamsSchema.compile!(%{count: {:integer, minimum: 1}})
      iex> ExParamsSchema.Parser.parse([], schema)
      {:error, :invalid_params}
  """
  @spec parse(map(), Schema.t()) :: map_parse_result()
  def parse(params, %Schema{} = schema) when is_map(params) do
    parse_with(params, schema, &reject_unknown_fields/3, &validate/2, &unwrap_cast_error/1)
  end

  def parse(_params, %Schema{}), do: {:error, :invalid_params}

  @doc """
  入力 map を変換・検証し、失敗時にはパスと制約を含むエラーを返します。

      iex> schema = ExParamsSchema.compile!(%{count: {:integer, minimum: 1, error: :invalid_count}})
      iex> {:error, [error]} = ExParamsSchema.Parser.parse_detailed(%{"count" => "0"}, schema)
      iex> {error.path, error.keyword, error.reason}
      {["count"], :minimum, :invalid_count}
  """
  @spec parse_detailed(map(), Schema.t()) :: detailed_parse_result()
  def parse_detailed(params, %Schema{} = schema) when is_map(params) do
    unknown_errors = unknown_field_errors(params, schema.fields, schema.strict)

    case ValueCaster.cast_fields_detailed(params, schema.fields) do
      {:ok, parsed} when unknown_errors == [] ->
        case validate_detailed(schema, parsed) do
          :ok -> {:ok, parsed}
          {:error, errors} -> {:error, errors}
        end

      {:ok, _parsed} ->
        {:error, unknown_errors}

      {:error, errors} ->
        {:error, unknown_errors ++ errors}
    end
  end

  def parse_detailed(_params, %Schema{}) do
    {:error, [%ExParamsSchema.ValidationError{path: [], keyword: :cast, reason: :invalid_params}]}
  end

  @spec parse_with(
          map(),
          Schema.t(),
          (map(), [Field.t()], boolean() -> :ok | {:error, term()}),
          (Schema.t(), map() -> :ok | {:error, term()}),
          (term() -> term())
        ) :: map_parse_result() | detailed_parse_result()
  defp parse_with(params, schema, reject_unknown, validate, normalize_cast_error) do
    with :ok <- reject_unknown.(params, schema.fields, schema.strict),
         {:ok, parsed} <- ValueCaster.cast_fields(params, schema.fields),
         :ok <- validate.(schema, parsed) do
      {:ok, parsed}
    else
      {:error, {path, reason}} when is_list(path) -> normalize_cast_error.({path, reason})
      {:error, reason} -> normalize_cast_error.(reason)
    end
  end

  @spec reject_unknown_fields(map(), [Field.t()], boolean()) ::
          :ok | {:error, ExParamsSchema.error_reason()}
  defp reject_unknown_fields(_params, _fields, false), do: :ok

  defp reject_unknown_fields(params, fields, true) do
    case Field.unknown_input_key(params, fields) do
      nil -> :ok
      key -> {:error, {:unknown_param, key}}
    end
  end

  @spec unknown_field_errors(map(), [Field.t()], boolean()) :: [ExParamsSchema.ValidationError.t()]
  defp unknown_field_errors(_params, _fields, false), do: []

  defp unknown_field_errors(params, fields, true) do
    allowed_keys =
      fields
      |> Enum.flat_map(fn field -> [Field.input_key(field), field.name] end)
      |> MapSet.new()

    params
    |> Map.keys()
    |> Enum.reject(&MapSet.member?(allowed_keys, &1))
    |> Enum.sort_by(&unknown_field_path/1)
    |> Enum.map(&unknown_field_error/1)
  end

  @spec validate(Schema.t(), map()) :: :ok | {:error, ExParamsSchema.error_reason()}
  defp validate(schema, parsed) do
    schema
    |> Schema.validation_data(parsed)
    |> then(&Validator.validate(schema, &1))
  end

  @spec validate_detailed(Schema.t(), map()) :: :ok | {:error, [ExParamsSchema.ValidationError.t()]}
  defp validate_detailed(schema, parsed) do
    schema
    |> Schema.validation_data(parsed)
    |> then(&Validator.validate_detailed(schema, &1))
  end

  defp unwrap_cast_error({path, reason}) when is_list(path), do: {:error, reason}
  defp unwrap_cast_error(%ExParamsSchema.ValidationError{reason: reason}), do: {:error, reason}
  defp unwrap_cast_error(reason), do: {:error, reason}

  @spec unknown_field_error(term()) :: ExParamsSchema.ValidationError.t()
  defp unknown_field_error(key) do
    %ExParamsSchema.ValidationError{
      path: [unknown_field_path(key)],
      keyword: :additional_properties,
      reason: {:unknown_param, key},
      details: %{key: key}
    }
  end

  defp unknown_field_path(key) when is_binary(key), do: key
  defp unknown_field_path(key) when is_atom(key), do: Atom.to_string(key)
  defp unknown_field_path(key), do: inspect(key)
end
