defmodule ExParamsSchema.Definition do
  @moduledoc """
  DSL と map 形式のフィールド定義を正規化・検証します。

  このモジュールは関連する機能をまとめる入口です。個別の処理は
  `Normalizer`、`Validator`、`Compiler` に分割されています。
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

  @doc "DSL option と JSON Schema keyword の対応を返します。"
  @spec json_schema_options() :: Keyword.t(String.t())
  defdelegate json_schema_options(), to: Options

  @doc "1 つの型定義を型と option に分解し、内部表現へ正規化します。"
  @spec normalize!(ExParamsSchema.definition()) :: normalized_definition()
  defdelegate normalize!(definition), to: Normalizer

  @doc "map 形式のスキーマをフィールド定義のリストへ変換します。"
  @spec fields_from_map!(%{required(atom()) => ExParamsSchema.definition()}) ::
          [ExParamsSchema.field()]
  defdelegate fields_from_map!(schema), to: Normalizer

  @doc "フィールド定義全体を正規化し、名前と入力キーの重複を検証します。"
  @spec normalize_fields!([ExParamsSchema.field()]) :: [ExParamsSchema.field()]
  defdelegate normalize_fields!(fields), to: Validator

  @doc "フィールド定義をパーサーが利用する構造体へコンパイルします。"
  @spec compile_fields!([ExParamsSchema.field()]) :: [ExParamsSchema.Definition.Field.t()]
  defdelegate compile_fields!(fields), to: Compiler

  @doc "map 形式のスキーマ定義を検証済みフィールドへコンパイルします。"
  @spec compile!(%{required(atom()) => ExParamsSchema.definition()}) :: [ExParamsSchema.Definition.Field.t()]
  def compile!(schema) when is_map(schema) do
    schema
    |> fields_from_map!()
    |> compile_fields!()
  end
end
