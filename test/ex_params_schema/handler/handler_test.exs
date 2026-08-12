defmodule ExParamsSchema.HandlerTest do
  use ExUnit.Case, async: true

  test "注釈を対応外のcallbackまたはprivate callbackに付けるとコンパイルに失敗する" do
    assert_compile_error(
      """
      @params_schema %{}
      def handle_event(_event, _params), do: :ok
      """,
      ~r/@params_schema supports handle_event\/3, handle_params\/3, and handle_info\/2, got: handle_event\/2/
    )

    assert_compile_error(
      """
      @params_schema %{}
      defp handle_event(_event, _params, _socket), do: :ok
      """,
      ~r/@params_schema supports handle_event\/3, handle_params\/3, and handle_info\/2, got: handle_event\/3/
    )
  end

  test "on_errorにはatomまたはnilだけを指定できる" do
    module = unique_module("InvalidErrorHandler")

    assert_raise ArgumentError, ~r/on_error must be an atom or nil, got: "on_params_error"/, fn ->
      Code.compile_string("""
      defmodule #{inspect(module)} do
        use ExParamsSchema.Handler, on_error: "on_params_error"
      end
      """)
    end
  end

  test "useオプションはkeyword listと既知のキーだけを許可する" do
    invalid_options_module = unique_module("InvalidOptions")
    unknown_option_module = unique_module("UnknownOption")

    assert_raise ArgumentError, "use ExParamsSchema.Handler options must be a keyword list", fn ->
      Code.compile_string("""
      defmodule #{inspect(invalid_options_module)} do
        use ExParamsSchema.Handler, :invalid
      end
      """)
    end

    assert_raise ArgumentError,
                 "use ExParamsSchema.Handler options cannot contain unknown keys. Allowed keys: :on_error",
                 fn ->
                   Code.compile_string("""
                   defmodule #{inspect(unknown_option_module)} do
                     # typos:ignore-next-line
                     use ExParamsSchema.Handler, on_erorr: :handle_params_error
                   end
                   """)
                 end
  end

  test "注釈付きcallbackはparamsとhandle_infoのpayloadを変数へ束縛する必要がある" do
    assert_compile_error(
      """
      @params_schema %{}
      def handle_event(_event, %{}, _socket), do: :ok
      """,
      ~r/must bind the annotated params to a variable/
    )

    assert_compile_error(
      """
      @params_schema %{}
      def handle_info({:updated, %{}}, _socket), do: :ok
      """,
      ~r/must bind handle_info\/2 payload to a params variable/
    )
  end

  test "複数clause、guard、注釈なしclauseの選択を維持する" do
    module =
      compile_handler!("""
      @params_schema %{count: {:integer, minimum: 1, error: :invalid_count}}
      def handle_event("typed", params, socket) when is_map(params), do: {:typed, params, socket}

      def handle_event("typed", params, socket), do: {:untyped, params, socket}
      def handle_event("raw", params, socket), do: {:raw, params, socket}
      """)

    assert {:typed, %{count: 2}, :socket} =
             module.handle_event("typed", %{"count" => "2"}, :socket)

    assert {:noreply, :socket} = module.handle_event("typed", %{"count" => "0"}, :socket)
    assert {:untyped, "not-a-map", :socket} = module.handle_event("typed", "not-a-map", :socket)

    raw_params = %{"count" => "not parsed"}
    assert {:raw, ^raw_params, :socket} = module.handle_event("raw", raw_params, :socket)
  end

  test "注釈は直後のclauseだけで一度消費し、map schemaでもguardとon_errorを維持する" do
    module =
      compile_handler!(
        """
        @params_schema %{count: {:integer, minimum: 1, error: :invalid_count}}
        def handle_event("typed", params, socket) when is_map(params), do: {:typed, params, socket}

        def handle_event("typed", params, socket), do: {:fallback, params, socket}
        def handle_event("raw", params, socket), do: {:raw, params, socket}

        defp on_params_error(event, reason, socket), do: {:error, {event, reason, socket}}
        """,
        on_error: :on_params_error
      )

    assert {:typed, %{count: 2}, :socket} =
             module.handle_event("typed", %{"count" => "2"}, :socket)

    assert {:error, {"typed", :invalid_count, :socket}} =
             module.handle_event("typed", %{"count" => "0"}, :socket)

    assert {:fallback, "not-a-map", :socket} =
             module.handle_event("typed", "not-a-map", :socket)

    raw_params = %{"count" => "not parsed"}
    assert {:raw, ^raw_params, :socket} = module.handle_event("raw", raw_params, :socket)
  end

  test "モジュールschemaでもguard・on_error・注釈の消費順を維持する" do
    schema_module = unique_module("OneShotModuleSchema")
    handler_module = unique_module("OneShotModuleSchemaHandler")

    Code.compile_string("""
    defmodule #{inspect(schema_module)} do
      use ExParamsSchema

      defschema do
        field :count, :integer, minimum: 1, error: :invalid_count
      end
    end

    defmodule #{inspect(handler_module)} do
      use ExParamsSchema.Handler, on_error: :on_params_error

      @params_schema #{inspect(schema_module)}
      def handle_event("typed", params, socket) when is_map(params), do: {:typed, params, socket}

      def handle_event("typed", params, socket), do: {:fallback, params, socket}

      def handle_event("raw", params, socket), do: {:raw, params, socket}

      defp on_params_error(event, reason, socket), do: {:error, {event, reason, socket}}
    end
    """)

    assert {:typed, %{count: 2}, :socket} =
             handler_module.handle_event("typed", %{"count" => "2"}, :socket)

    assert {:error, {"typed", :invalid_count, :socket}} =
             handler_module.handle_event("typed", %{"count" => "0"}, :socket)

    assert {:fallback, "not-a-map", :socket} =
             handler_module.handle_event("typed", "not-a-map", :socket)

    raw_params = %{"count" => "not parsed"}
    assert {:raw, ^raw_params, :socket} = handler_module.handle_event("raw", raw_params, :socket)
  end

  test "モジュールschemaのエラーcallbackへeventと変換前paramsを渡す" do
    schema_module = unique_module("ModuleSchema")
    handler_module = unique_module("ModuleSchemaHandler")

    Code.compile_string("""
    defmodule #{inspect(schema_module)} do
      use ExParamsSchema

      defschema do
        field :count, :integer, minimum: 1, error: :invalid_count
      end
    end

    defmodule #{inspect(handler_module)} do
      use ExParamsSchema.Handler, on_error: :on_params_error

      @params_schema #{inspect(schema_module)}
      def handle_event(event, params, socket), do: {:ok, {event, params, socket}}

      defp on_params_error(event, reason, socket), do: {:error, {event, reason, socket}}
    end
    """)

    assert {:error, {"save", :invalid_count, :socket}} =
             handler_module.handle_event("save", %{"count" => "0"}, :socket)
  end

  test "map schemaのエラーcallbackへhandle_paramsとhandle_infoの変換前paramsを渡す" do
    module =
      compile_handler!(
        """
        @params_schema %{count: {:integer, minimum: 1, error: :invalid_count}}
        def handle_params(params, _uri, socket), do: {:ok, {params, socket}}

        @params_schema %{count: {:integer, minimum: 1, error: :invalid_count}}
        def handle_info({:updated, params}, socket), do: {:ok, {params, socket}}

        defp on_params_error(params, reason, socket), do: {:error, {params, reason, socket}}
        """,
        on_error: :on_params_error
      )

    params = %{"count" => "0"}

    assert {:error, {^params, :invalid_count, :socket}} =
             module.handle_params(params, "/devices", :socket)

    assert {:error, {^params, :invalid_count, :socket}} =
             module.handle_info({:updated, params}, :socket)
  end

  test "handle_infoのメッセージ全体をparams変数として変換できる" do
    module =
      compile_handler!("""
      @params_schema %{count: {:integer, minimum: 1}}
      def handle_info(params, socket), do: {:ok, {params, socket}}
      """)

    assert {:ok, {%{count: 2}, :socket}} = module.handle_info(%{"count" => "2"}, :socket)
    assert {:noreply, :socket} = module.handle_info(%{"count" => "0"}, :socket)
  end

  defp assert_compile_error(definition, message) do
    module = unique_module("InvalidHandler")

    assert_raise ArgumentError, message, fn ->
      Code.compile_string("""
      defmodule #{inspect(module)} do
        use ExParamsSchema.Handler

        #{definition}
      end
      """)
    end
  end

  defp compile_handler!(definition, options \\ []) do
    module = unique_module("Handler")
    options = Keyword.put_new(options, :on_error, nil)

    Code.compile_string("""
    defmodule #{inspect(module)} do
      use ExParamsSchema.Handler, #{inspect(options)}

      #{definition}
    end
    """)

    module
  end

  defp unique_module(suffix) do
    Module.concat(__MODULE__, "#{suffix}#{System.unique_integer([:positive])}")
  end
end
