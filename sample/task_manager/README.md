# Task Manager sample

This is a minimal Mix project that uses `ExParamsSchema` to convert task creation
form inputs into application values. It demonstrates using the same schema for
both a conventional API and LiveView.

## Running the sample

Run the following from the repository root:

```shell
cd examples/task_manager
mix deps.get
mix run -e 'TaskManager.print()'
mix test
```

The output demonstrates:

- Conversion of form-like strings into integers, dates, booleans, and atom enums
- Validation of a list of labels and a nested schedule map
- Validation errors with paths returned by `parse_detailed/1`
- JSON Schema Draft 7 generated from the declared schema
- The API's `create/1` and LiveView's `handle_event/3` and `handle_info/2`
  receiving the same typed task

## Key files

- `lib/task_manager/tasks/create_params.ex`: Input schema for task creation
- `lib/task_manager_web/api/tasks_controller.ex`: API handling that explicitly calls `parse/1`
- `lib/task_manager_web/live/task_live.ex`: `handle_event/3` and `handle_info/2` using `@params_schema`
- `lib/task_manager.ex`: Valid and invalid sample inputs, plus output formatting

In an actual Phoenix LiveView application, add `use Phoenix.LiveView` to
`TaskManagerWeb.TaskLive` and update the socket with `assign/3`. The location
of the params schema and the callback structure remain the same.
