defmodule ExParamsSchema.HandlerIntegrationTest do
  use ExUnit.Case, async: true

  defmodule Params do
    use ExParamsSchema

    defschema do
      field :fixture_id, :integer, source: "fixture-id", minimum: 1, error: :invalid_fixture
      field :level, :integer, minimum: 0, maximum: 255, error: :invalid_level
      field :mode, :string, enum: ["merge", "replace"], error: :invalid_mode
    end
  end

  defmodule AnnotatedHandler do
    use ExParamsSchema.Handler, on_error: :handle_event_params_error

    @params_schema Params
    def handle_event("example", params, socket), do: {:noreply, {params, socket}}

    defp handle_event_params_error(event, reason, socket), do: {:error, {event, reason, socket}}
  end

  defmodule DefaultErrorHandler do
    use ExParamsSchema.Handler

    @params_schema Params
    def handle_event("example", params, socket) when is_map(params),
      do: {:noreply, {params, socket}}

    def handle_event("raw", params, socket), do: {:noreply, {params, socket}}
    def handle_event("plain", params, socket), do: {:noreply, {params, socket}}

    @params_schema Params
    def handle_params(params, _uri, socket), do: {:noreply, {params, socket}}

    @params_schema Params
    def handle_info({:example, params}, socket), do: {:noreply, {params, socket}}

    def handle_info(:plain, socket), do: {:noreply, socket}
  end

  defmodule MapSchemaHandler do
    use ExParamsSchema.Handler

    @params_schema %{
      fixture_id: {:integer, source: "fixture-id", minimum: 1, error: :invalid_fixture},
      enabled: {:boolean, default: false}
    }
    def handle_event("example", params, socket), do: {:noreply, {params, socket}}
  end

  test "変換結果とエラーをhandle_eventへ接続する" do
    assert {:noreply, {%Params{level: 128}, :socket}} =
             AnnotatedHandler.handle_event("example", valid_params(), :socket)

    assert {:error, {"example", :invalid_level, :socket}} =
             AnnotatedHandler.handle_event("example", valid_params(%{"level" => "999"}), :socket)
  end

  test "デフォルトのエラー処理、guard、未注釈clauseを扱う" do
    assert {:noreply, :socket} =
             DefaultErrorHandler.handle_event("example", %{"level" => "999"}, :socket)

    assert {:noreply, {%Params{level: 128}, :socket}} =
             DefaultErrorHandler.handle_event("example", valid_params(), :socket)

    raw_params = %{"level" => "not parsed"}

    assert {:noreply, {^raw_params, :socket}} =
             DefaultErrorHandler.handle_event("raw", raw_params, :socket)

    assert {:noreply, {^raw_params, :socket}} =
             DefaultErrorHandler.handle_event("plain", raw_params, :socket)
  end

  test "handle_paramsとhandle_infoのpayloadを変換する" do
    params = valid_params()

    assert {:noreply, {%Params{level: 128}, :socket}} =
             DefaultErrorHandler.handle_params(params, "/console", :socket)

    assert {:noreply, {%Params{level: 128}, :socket}} =
             DefaultErrorHandler.handle_info({:example, params}, :socket)

    assert {:noreply, :socket} = DefaultErrorHandler.handle_info(:plain, :socket)
    assert {:noreply, :socket} = DefaultErrorHandler.handle_info({:example, %{}}, :socket)
  end

  test "スキーマ定義のmapを指定して変換する" do
    assert {:noreply, {%{fixture_id: 12, enabled: false}, :socket}} =
             MapSchemaHandler.handle_event("example", %{"fixture-id" => "12"}, :socket)

    assert {:noreply, :socket} =
             MapSchemaHandler.handle_event("example", %{"fixture-id" => "0"}, :socket)
  end

  defp valid_params(overrides \\ %{}) do
    Map.merge(%{"fixture-id" => "1", "level" => "128", "mode" => "merge"}, overrides)
  end
end
