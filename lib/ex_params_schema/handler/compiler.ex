defmodule ExParamsSchema.Handler.Compiler do
  @moduledoc """
  Expands `ExParamsSchema.Handler` annotations into callback implementations.

  This internal compile-time-only module rewrites LiveView callbacks.
  """

  alias ExParamsSchema.Handler.Compiler.Clause
  alias ExParamsSchema.Handler.Compiler.Source

  @supported_callbacks handle_event: 3, handle_params: 3, handle_info: 2
  @supported_callbacks_message @supported_callbacks
                               |> Enum.map(fn {name, arity} -> "#{name}/#{arity}" end)
                               |> List.update_at(-1, &("and " <> &1))
                               |> Enum.join(", ")

  @type callback :: {atom(), non_neg_integer()}

  def on_definition(env, :def, name, args, guards, body)
      when {name, length(args)} in @supported_callbacks do
    clause = Clause.new(name, args, guards, body, take_schema(env.module))
    Module.put_attribute(env.module, :event_param_clauses, clause)
  end

  def on_definition(env, _kind, name, args, _guards, _body) do
    case take_schema(env.module) do
      :passthrough ->
        :ok

      _typed ->
        raise ArgumentError,
              "@params_schema supports #{@supported_callbacks_message}, got: " <>
                "#{name}/#{length(args)}"
    end
  end

  defmacro __before_compile__(env) do
    clauses =
      env.module
      |> Module.get_attribute(:event_param_clauses)
      |> Enum.reverse()

    clauses
    |> callbacks_requiring_rewrite()
    |> Enum.flat_map(&rewrite_callback(&1, clauses, env.module))
  end

  @spec take_schema(module()) :: Clause.mode()
  defp take_schema(module) do
    mode =
      case Module.get_attribute(module, :params_schema) do
        nil -> :passthrough
        schema -> {:typed, schema}
      end

    Module.delete_attribute(module, :params_schema)
    mode
  end

  @spec callbacks_requiring_rewrite([Clause.t()]) :: [callback()]
  defp callbacks_requiring_rewrite(clauses) do
    clauses
    |> Enum.filter(&Clause.typed?/1)
    |> Enum.map(&Clause.callback/1)
    |> Enum.uniq()
  end

  @spec rewrite_callback(callback(), [Clause.t()], module()) :: [Macro.t()]
  defp rewrite_callback({name, arity} = callback, clauses, module) do
    rewritten_clauses =
      clauses
      |> Enum.filter(&(Clause.callback(&1) == callback))
      |> Enum.map(&rewrite_clause(&1, module))

    [make_overridable(name, arity) | rewritten_clauses]
  end

  @spec make_overridable(atom(), non_neg_integer()) :: Macro.t()
  defp make_overridable(name, arity) do
    quote do
      defoverridable [{unquote(name), unquote(arity)}]
    end
  end

  @spec rewrite_clause(Clause.t(), module()) :: Macro.t()
  defp rewrite_clause(%Clause{name: name, args: args, guards: guards, definition: definition, mode: mode}, module) do
    head = callback_head(name, args, guards)
    rewritten_definition = rewrite_definition(mode, name, args, definition, module)

    quote do
      Kernel.def(unquote(head), unquote(rewritten_definition))
    end
  end

  @spec rewrite_definition(Clause.mode(), atom(), [Macro.t()], term(), module()) :: term()
  defp rewrite_definition(:passthrough, _name, _args, definition, _module),
    do: definition

  defp rewrite_definition({:typed, schema}, name, args, definition, module) do
    {params, error_source, socket} = callback_arguments!(name, args, module)
    ensure_variable!(params, module)

    parsed_params = Macro.unique_var(:parsed_params, __MODULE__)
    reason = Macro.unique_var(:reason, __MODULE__)
    error_handler = Module.get_attribute(module, :params_schema_error_handler)
    body = Keyword.fetch!(definition, :do)

    parse = schema |> Source.new() |> Source.parse_expression(params)

    rewritten_body =
      quote do
        case unquote(parse) do
          {:ok, unquote(parsed_params)} ->
            unquote(params) = unquote(parsed_params)
            unquote(body)

          {:error, unquote(reason)} ->
            unquote(error_body(error_handler, error_source, reason, socket))
        end
      end

    Keyword.put(definition, :do, rewritten_body)
  end

  @spec callback_arguments!(atom(), [Macro.t()], module()) :: {Macro.t(), Macro.t(), Macro.t()}
  defp callback_arguments!(:handle_event, [event, params, socket], _module), do: {params, event, socket}

  defp callback_arguments!(:handle_params, [params, _uri, socket], _module),
    do: {params, params, socket}

  defp callback_arguments!(:handle_info, [message, socket], module) do
    params = params_variable_from_message!(message, module)
    {params, params, socket}
  end

  @spec params_variable_from_message!(Macro.t(), module()) :: Macro.t()
  defp params_variable_from_message!({name, _meta, context} = variable, _module)
       when is_atom(name) and is_atom(context),
       do: variable

  defp params_variable_from_message!(pattern, module) do
    find_named_variable(pattern, :params) ||
      raise ArgumentError,
            "#{inspect(module)} must bind handle_info/2 payload to a params variable"
  end

  @spec find_named_variable(Macro.t(), atom()) :: Macro.t() | nil
  defp find_named_variable(ast, target_name) do
    {_ast, found} =
      Macro.prewalk(ast, nil, fn
        {^target_name, _meta, context} = variable, nil when is_atom(context) ->
          {variable, variable}

        node, found ->
          {node, found}
      end)

    found
  end

  @spec callback_head(atom(), [Macro.t()], [Macro.t()]) :: Macro.t()
  defp callback_head(name, args, []), do: {name, [], args}

  defp callback_head(name, args, guards) do
    {:when, [], [{name, [], args} | guards]}
  end

  @spec ensure_variable!(Macro.t(), module()) :: :ok
  defp ensure_variable!({name, _meta, context}, _module) when is_atom(name) and is_atom(context),
    do: :ok

  defp ensure_variable!(params, module) do
    raise ArgumentError,
          "#{inspect(module)} must bind the annotated params to a variable, got: " <>
            Macro.to_string(params)
  end

  @spec error_body(atom() | nil, Macro.t(), Macro.t(), Macro.t()) :: Macro.t()
  defp error_body(nil, _source, _reason, socket) do
    quote do: {:noreply, unquote(socket)}
  end

  defp error_body(handler, source, reason, socket) when is_atom(handler) do
    {handler, [generated: true], [source, reason, socket]}
  end
end
