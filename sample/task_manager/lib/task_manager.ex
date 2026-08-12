defmodule TaskManager do
  @moduledoc """
  Entry point for the task-management sample runnable with `mix run`.
  """

  alias TaskManager.Tasks.CreateParams
  alias TaskManagerWeb.{Api.TasksController, TaskLive}

  @spec run() :: map()
  def run do
    params = valid_params()
    {:created, api_task} = TasksController.create(params)
    {:noreply, event_socket} = TaskLive.handle_event("create_task", params, %{})
    {:noreply, info_socket} = TaskLive.handle_info({:task_synced, params}, %{})

    %{
      api_task: api_task,
      live_event_task: event_socket.task,
      live_info_task: info_socket.synced_task,
      errors: invalid_params() |> CreateParams.parse_detailed(),
      schema: CreateParams.json_schema()
    }
  end

  @spec print() :: :ok
  def print do
    result = run()

    IO.puts("Tasks cast by the API and LiveView:")

    IO.inspect(%{
      api: result.api_task,
      handle_event: result.live_event_task,
      handle_info: result.live_info_task
    })

    IO.puts("\nDetailed errors:")
    IO.inspect(result.errors)
    IO.puts("\nRequired JSON Schema fields:")
    IO.inspect(result.schema["required"])
  end

  defp valid_params do
    %{
      "task-id" => "42",
      "title" => "Review release notes",
      "priority" => "high",
      "estimate-minutes" => "90",
      "labels" => ["release", "documentation"],
      "schedule" => %{"due-on" => "2026-08-15", "notify-assignee" => "true"}
    }
  end

  defp invalid_params do
    Map.put(valid_params(), "priority", "urgent")
  end
end
