defmodule ExParamsSchema.Handler.Compiler.Clause do
  @moduledoc false

  @type mode :: :passthrough | {:typed, term()}

  @type t :: %__MODULE__{
          name: atom(),
          args: [Macro.t()],
          guards: [Macro.t()],
          definition: keyword(Macro.t()),
          mode: mode()
        }

  defstruct [:name, :args, :guards, :definition, :mode]

  @spec new(atom(), [Macro.t()], [Macro.t()], keyword(Macro.t()), mode()) :: t()
  def new(name, args, guards, definition, mode) do
    %__MODULE__{
      name: name,
      args: args,
      guards: guards,
      definition: definition,
      mode: mode
    }
  end

  @spec callback(t()) :: {atom(), non_neg_integer()}
  def callback(%__MODULE__{name: name, args: args}), do: {name, length(args)}

  @spec typed?(t()) :: boolean()
  def typed?(%__MODULE__{mode: {:typed, _schema}}), do: true
  def typed?(%__MODULE__{}), do: false
end
