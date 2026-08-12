defmodule TaskManagerTest do
  use ExUnit.Case, async: true

  alias TaskManagerWeb.{Api.TasksController, TaskLive}

  @valid_params %{
    "task-id" => "42",
    "title" => "Review release notes",
    "priority" => "high",
    "estimate-minutes" => "90",
    "labels" => ["release", "documentation"],
    "schedule" => %{"due-on" => "2026-08-15", "notify-assignee" => "true"}
  }

  test "API, handle_event, and handle_info receive the same typed task" do
    result = TaskManager.run()

    expected_task = %{
      task_id: 42,
      title: "Review release notes",
      priority: :high,
      estimate_minutes: 90,
      labels: ["release", "documentation"],
      schedule: %{due_on: ~D[2026-08-15], notify_assignee: true}
    }

    assert result.api_task == expected_task
    assert result.live_event_task == expected_task
    assert result.live_info_task == expected_task
  end

  test "API returns a 422-equivalent result for invalid params" do
    params = Map.put(@valid_params, "priority", "urgent")

    assert {:unprocessable_entity, %{error: :invalid_priority}} = TasksController.create(params)
  end

  test "LiveView callbacks handle params errors for both events and info messages" do
    params = Map.put(@valid_params, "priority", "urgent")

    assert {:noreply, %{params_error: %{source: "create_task", reason: :invalid_priority}}} =
             TaskLive.handle_event("create_task", params, %{})

    assert {:noreply, %{params_error: %{source: ^params, reason: :invalid_priority}}} =
             TaskLive.handle_info({:task_synced, params}, %{})
  end

  test "invalid input returns detailed errors with paths" do
    assert {:error, errors} = TaskManager.run().errors
    assert [%{path: ["priority"], keyword: :cast, reason: :invalid_priority}] = errors
  end

  test "generates JSON Schema" do
    schema = TaskManager.run().schema

    assert schema["type"] == "object"
    assert "task_id" in schema["required"]
    assert get_in(schema, ["properties", "labels", "uniqueItems"])
  end
end
