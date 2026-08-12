defmodule ExParamsSchema.Definition do
  @moduledoc """
  Normalizes and validates field definitions written in the DSL and map forms.

  This module is the entry point for the related functionality. Individual operations are
  split among `Normalizer`, `Validator`, and `Compiler`.
  """

  alias ExParamsSchema.Definition.{Compiler, Normalizer, Options, Validator}

  @typedoc false
  @type definition_path :: [String.t()]

  @typedoc false
  @type input_key :: String.t() | atom()

  @type normalized_definition :: {
          type :: ExParamsSchema.field_type(),
          options :: ExParamsSchema.field_options()
        }

  @doc "Returns the mapping between DSL options and JSON Schema keywords."
  @spec json_schema_options() :: Keyword.t(String.t())
  defdelegate json_schema_options(), to: Options

  @doc "Splits a type definition into its type and options and normalizes it to the internal representation."
  @spec normalize!(ExParamsSchema.definition()) :: normalized_definition()
  defdelegate normalize!(definition), to: Normalizer

  @doc "Converts a map-based schema into a list of field definitions."
  @spec fields_from_map!(%{required(atom()) => ExParamsSchema.definition()}) ::
          [ExParamsSchema.field()]
  defdelegate fields_from_map!(schema), to: Normalizer

  @doc "Normalizes all field definitions and validates unique names and input keys."
  @spec normalize_fields!([ExParamsSchema.field()]) :: [ExParamsSchema.field()]
  defdelegate normalize_fields!(fields), to: Validator

  @doc "Compiles field definitions into structs used by the parser."
  @spec compile_fields!([ExParamsSchema.field()]) :: [ExParamsSchema.Definition.Field.t()]
  defdelegate compile_fields!(fields), to: Compiler

  @doc "Compiles a map-based schema definition into validated fields."
  @spec compile!(%{required(atom()) => ExParamsSchema.definition()}) :: [ExParamsSchema.Definition.Field.t()]
  def compile!(schema) when is_map(schema) do
    schema
    |> fields_from_map!()
    |> compile_fields!()
  end
end
