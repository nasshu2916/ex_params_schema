defmodule ExParamsSchema.Schema.Defaults do
  @moduledoc """
  Casts field defaults and validates them against the generated JSON Schema.

  This internal module is used while compiling schemas.
  """

  alias ExParamsSchema.Definition.Field
  alias ExParamsSchema.Schema
  alias ExParamsSchema.Schema.Projector

  defmodule Context do
    @enforce_keys [:resolved]
    defstruct [
      :resolved,
      schema_path: ["properties"],
      field_path: [],
      reason: nil
    ]

    @type t() :: %__MODULE__{
            resolved: ExJsonSchema.Schema.Root.t(),
            schema_path: [String.t()],
            field_path: [String.t()],
            reason: ExParamsSchema.error_reason() | nil
          }
  end

  @doc """
  default 値をフィールド型へ変換し、対応する JSON Schema で検証します。

      iex> fields = ExParamsSchema.Definition.compile_fields!([
      ...>   {:count, :integer, [default: "2", minimum: 1]}
      ...> ])
      iex> {json_schema, _errors} = ExParamsSchema.Schema.JsonSchema.build(fields, false)
      iex> resolved = ExJsonSchema.Schema.resolve(json_schema)
      iex> [field] = ExParamsSchema.Schema.Defaults.normalize!(fields, resolved)
      iex> Keyword.fetch!(field.options, :default)
      2

  変換できない値や制約を満たさない値は `ArgumentError` になります。
  """
  @spec normalize!([Field.t()], ExJsonSchema.Schema.Root.t()) :: [Field.t()]
  def normalize!(fields, resolved) do
    normalize_fields!(fields, %Context{resolved: resolved})
  end

  @spec normalize_fields!([Field.t()], Context.t()) :: [Field.t()]
  defp normalize_fields!(fields, %Context{} = context) do
    Enum.map(fields, &normalize_field!(&1, context))
  end

  @spec normalize_field!(Field.t(), Context.t()) :: Field.t()
  defp normalize_field!(%Field{} = field, %Context{} = context) do
    context = field_context(context, field)
    type = normalize_nested!(field.type, context)
    options = normalize_default!(type, field.options, context)

    %Field{field | type: type, options: options}
  end

  @spec field_context(Context.t(), Field.t()) :: Context.t()
  defp field_context(%Context{} = context, field) do
    name = Atom.to_string(field.name)

    %Context{
      context
      | schema_path: context.schema_path ++ [name],
        field_path: context.field_path ++ [name],
        reason: Field.error_reason(field, context.reason)
    }
  end

  @spec normalize_nested!(Field.normalized_type(), Context.t()) :: Field.normalized_type()
  defp normalize_nested!({:array, type, options}, %Context{} = context) do
    context = array_item_context(context, options)
    type = normalize_nested!(type, context)
    options = normalize_default!(type, options, context)

    {:array, type, options}
  end

  defp normalize_nested!({:object, fields}, %Context{} = context) do
    fields = normalize_fields!(fields, %{context | schema_path: context.schema_path ++ ["properties"]})

    {:object, fields}
  end

  defp normalize_nested!(type, _context), do: type

  @spec array_item_context(Context.t(), ExParamsSchema.field_options()) :: Context.t()
  defp array_item_context(%Context{} = context, options) do
    %Context{
      context
      | schema_path: context.schema_path ++ ["items"],
        field_path: context.field_path ++ ["[]"],
        reason: Keyword.get(options, :error, context.reason)
    }
  end

  @spec normalize_default!(Field.normalized_type(), ExParamsSchema.field_options(), Context.t()) ::
          ExParamsSchema.field_options()
  defp normalize_default!(type, options, %Context{} = context) do
    case Keyword.fetch(options, :default) do
      {:ok, default} ->
        normalize_default_value!(default, type, options, context)

      :error ->
        options
    end
  end

  @spec normalize_default_value!(
          ExParamsSchema.value(),
          Field.normalized_type(),
          ExParamsSchema.field_options(),
          Context.t()
        ) :: ExParamsSchema.field_options()
  defp normalize_default_value!(default, type, options, %Context{} = context) do
    with {:ok, parsed} <- ExParamsSchema.ValueCaster.cast(default, type, options, context.reason),
         :ok <- validate_default(context, type, parsed) do
      Keyword.put(options, :default, parsed)
    else
      {:error, _reason} -> raise_invalid_default!(context.field_path, default)
    end
  end

  @spec validate_default(Context.t(), Field.normalized_type(), ExParamsSchema.value()) ::
          :ok | {:error, :invalid_default}
  defp validate_default(%Context{} = context, type, value) do
    fragment = "#/" <> Enum.map_join(context.schema_path, "/", &Schema.JsonPointer.escape_segment/1)
    projected = Projector.project_value(type, value)

    case ExJsonSchema.Validator.validate_fragment(context.resolved, fragment, projected, error_formatter: false) do
      :ok -> :ok
      {:error, _errors} -> {:error, :invalid_default}
    end
  end

  @spec raise_invalid_default!([String.t()], ExParamsSchema.value()) :: no_return()
  defp raise_invalid_default!(field_path, default) do
    raise ArgumentError, "invalid default at #{Enum.join(field_path, ".")}: #{inspect(default)}"
  end
end
