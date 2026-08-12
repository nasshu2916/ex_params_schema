defmodule ExParamsSchema.Handler do
  @moduledoc """
  Associates params schemas with supported callbacks and casts received values.

  Place `@params_schema` immediately before a supported callback to call `parse/1` before entering
  its body. A module schema binds a struct to the callback's params, while a map schema definition
  binds a map.

      use ExParamsSchema.Handler

      @params_schema Params.Update
      def handle_event("update", params, socket) do
        params.id
        {:noreply, socket}
      end

  ## Supported callbacks

  `@params_schema` can be specified only for public `handle_event/3`, `handle_params/3`, and
  `handle_info/2` callbacks. Bind the second argument of `handle_event/3` and the first argument
  of `handle_params/3` to variables. Bind the tuple payload of `handle_info/2` to a variable named
  `params`.

      @params_schema Params.RecordUpdate
      def handle_info({:record_update, params}, socket) do
        params.id
        {:noreply, socket}
      end

  Callback clauses without the annotation are not transformed.

  ## Error handling

  To handle parse errors, specify an error handler for the module.

      use ExParamsSchema.Handler,
        on_error: :handle_params_error

  The error handler is called as `handler(source, reason, socket)`. For `handle_event/3`, `source`
  is the event name; for `handle_params/3` and `handle_info/2`, it is the params before casting.
  The handler must return a value appropriate for the callback, usually `{:noreply, socket}`.

  When `on_error:` is omitted, parse errors return `{:noreply, socket}`.

  ## Compile-time errors

  Specifying `@params_schema` on an unsupported function, a private function, or an unsupported
  callback arity raises `ArgumentError`. It also raises `ArgumentError` when the params to be
  cast are not bound to variables, or when the `handle_info/2` payload is not bound to `params`.
  """

  @doc """
  Enables automatic parameter casting for callbacks.

  Set `on_error:` to the atom name of the function called on parse errors. Define the function as
  `handler(source, reason, socket)`.
  """
  defmacro __using__(options) do
    validate_options!(options)
    error_handler = error_handler!(options)

    quote do
      Module.register_attribute(__MODULE__, :params_schema, accumulate: false)
      Module.register_attribute(__MODULE__, :event_param_clauses, accumulate: true)

      @params_schema_error_handler unquote(error_handler)
      @on_definition {ExParamsSchema.Handler.Compiler, :on_definition}
      @before_compile ExParamsSchema.Handler.Compiler
    end
  end

  defp validate_options!(options) do
    unless Keyword.keyword?(options) do
      raise ArgumentError, "use ExParamsSchema.Handler options must be a keyword list"
    end

    unknown = Keyword.keys(options) -- [:on_error]

    unless unknown == [] do
      raise ArgumentError,
            "use ExParamsSchema.Handler options cannot contain unknown keys. Allowed keys: :on_error"
    end
  end

  defp error_handler!(options) do
    case Keyword.get(options, :on_error) do
      nil ->
        nil

      handler when is_atom(handler) ->
        handler

      handler ->
        raise ArgumentError,
              "on_error must be an atom or nil, got: #{inspect(handler)}"
    end
  end
end
