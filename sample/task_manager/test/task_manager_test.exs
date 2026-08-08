defmodule TaskManagerTest do
  use ExUnit.Case, async: true

  alias TaskManagerWeb.{Api.TasksController, TaskLive}

  @valid_params %{
    "task-id" => "42",
    "title" => "Release notes を確認する",
    "priority" => "high",
    "estimate-minutes" => "90",
    "labels" => ["release", "documentation"],
    "schedule" => %{"due-on" => "2026-08-15", "notify-assignee" => "true"}
  }

  test "API、handle_event、handle_info が同じ型付きタスクを受け取る" do
    result = TaskManager.run()

    expected_task = %{
      task_id: 42,
      title: "Release notes を確認する",
      priority: :high,
      estimate_minutes: 90,
      labels: ["release", "documentation"],
      schedule: %{due_on: ~D[2026-08-15], notify_assignee: true}
    }

    assert result.api_task == expected_task
    assert result.live_event_task == expected_task
    assert result.live_info_task == expected_task
  end

  test "API は不正な params を 422 相当の結果で返す" do
    params = Map.put(@valid_params, "priority", "urgent")

    assert {:unprocessable_entity, %{error: :invalid_priority}} = TasksController.create(params)
  end

  test "LiveView callback は event と info の両方で params エラーを処理する" do
    params = Map.put(@valid_params, "priority", "urgent")

    assert {:noreply, %{params_error: %{source: "create_task", reason: :invalid_priority}}} =
             TaskLive.handle_event("create_task", params, %{})

    assert {:noreply, %{params_error: %{source: ^params, reason: :invalid_priority}}} =
             TaskLive.handle_info({:task_synced, params}, %{})
  end

  test "不正な入力は path 付きの詳細エラーを返す" do
    assert {:error, errors} = TaskManager.run().errors
    assert [%{path: ["priority"], keyword: :cast, reason: :invalid_priority}] = errors
  end

  test "JSON Schema を生成する" do
    schema = TaskManager.run().schema

    assert schema["type"] == "object"
    assert "task_id" in schema["required"]
    assert get_in(schema, ["properties", "labels", "uniqueItems"])
  end
end
