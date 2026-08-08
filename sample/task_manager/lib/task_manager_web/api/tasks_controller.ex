defmodule TaskManagerWeb.Api.TasksController do
  @moduledoc """
  Task-creation handling for a JSON API.

  A Phoenix controller action can call `create/1` and translate `{:created, task}` or
  `{:unprocessable_entity, error}` into an HTTP response.
  """

  alias TaskManager.{Tasks, Tasks.CreateParams}

  @spec create(map()) :: {:created, map()} | {:unprocessable_entity, map()}
  def create(params) do
    case CreateParams.parse(params) do
      {:ok, parsed_params} -> {:created, Tasks.create(parsed_params)}
      {:error, reason} -> {:unprocessable_entity, %{error: reason}}
    end
  end
end
