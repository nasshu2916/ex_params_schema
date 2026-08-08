defmodule TaskManager.Tasks.CreateParams do
  @moduledoc """
  Schema that converts task-creation input into application values.
  """

  use ExParamsSchema

  defschema strict: true do
    field :task_id, :integer,
      source: "task-id",
      minimum: 1,
      maximum: 9_999_999,
      error: :invalid_task_id

    field :title, :string, min_length: 2, max_length: 120, error: :invalid_title
    field :priority, {:enum, [:low, :normal, :high]}, error: :invalid_priority

    field :estimate_minutes, :integer,
      source: "estimate-minutes",
      minimum: 0,
      maximum: 2_400,
      error: :invalid_estimate

    field :labels, [:string],
      min_items: 1,
      max_items: 8,
      unique_items: true,
      error: :invalid_labels

    field :schedule,
          %{
            due_on: {:date, source: "due-on", optional: true},
            notify_assignee: {:boolean, source: "notify-assignee", default: true}
          },
          strict: true,
          error: :invalid_schedule
  end
end
