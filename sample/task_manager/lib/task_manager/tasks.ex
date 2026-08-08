defmodule TaskManager.Tasks do
  @moduledoc """
  Shared application logic for tasks.
  """

  alias TaskManager.Tasks.CreateParams

  @spec create(CreateParams.t()) :: map()
  def create(params), do: Map.from_struct(params)
end
