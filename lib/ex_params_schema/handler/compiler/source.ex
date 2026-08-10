defmodule ExParamsSchema.Handler.Compiler.Source do
  @moduledoc false

  @type t :: {:compiled, ExParamsSchema.compiled_schema()} | {:module, term()}

  @spec new(term()) :: t()
  def new(schema) when is_map(schema), do: {:compiled, ExParamsSchema.compile!(schema)}
  def new(schema), do: {:module, schema}

  @spec parse_expression(t(), Macro.t()) :: Macro.t()
  def parse_expression({:compiled, schema}, params) do
    quote do
      ExParamsSchema.parse(unquote(params), unquote(Macro.escape(schema)))
    end
  end

  def parse_expression({:module, schema}, params) do
    quote do
      unquote(schema).parse(unquote(params))
    end
  end
end
