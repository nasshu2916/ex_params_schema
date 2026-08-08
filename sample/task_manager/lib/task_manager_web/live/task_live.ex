defmodule TaskManagerWeb.TaskLive do
  @moduledoc """
  Example of applying a params schema to LiveView callbacks.

  This standalone sample treats the socket as a map. In a Phoenix application, add
  `use Phoenix.LiveView` and replace `Map.put/3` with `assign/3`.
  """

  use ExParamsSchema.Handler, on_error: :handle_params_error

  alias TaskManager.{Tasks, Tasks.CreateParams}

  @params_schema CreateParams
  def handle_event("create_task", params, socket) do
    {:noreply, Map.put(socket, :task, Tasks.create(params))}
  end

  @params_schema CreateParams
  def handle_info({:task_synced, params}, socket) do
    {:noreply, Map.put(socket, :synced_task, Tasks.create(params))}
  end

  defp handle_params_error(source, reason, socket) do
    {:noreply, Map.put(socket, :params_error, %{source: source, reason: reason})}
  end
end
