defmodule ExParamsSchema.Handler do
  @moduledoc """
  LiveView callback に params schema を関連付け、受信値を変換します。

  `@params_schema` を対象 callback の直前に置くと、callback 本体へ入る前に `parse/1` を呼び出します。
  モジュールを指定した場合は構造体、スキーマ定義の map を指定した場合は map が callback の params に
  束縛されます。

      use ExParamsSchema.Handler

      @params_schema Params.Update
      def handle_event("update", params, socket) do
        params.id
        {:noreply, socket}
      end

  ## 対応 callback

  `@params_schema` は public な `handle_event/3`、`handle_params/3`、`handle_info/2` にだけ
  指定できます。`handle_event/3` の第 2 引数と `handle_params/3` の第 1 引数は、いずれも変数へ
  束縛してください。`handle_info/2` のタプル内 payload は `params` という変数名で束縛します。

      @params_schema Params.RecordUpdate
      def handle_info({:record_update, params}, socket) do
        params.id
        {:noreply, socket}
      end

  注釈のない callback clause は変換されません。

  ## エラー処理

  parse エラーを表示したい場合は、LiveView ごとにエラーハンドラーを指定できます。

      use ExParamsSchema.Handler,
        on_error: :handle_params_error

  エラーハンドラーは `handler(source, reason, socket)` として呼び出されます。`handle_event/3` の
  `source` はイベント名、`handle_params/3` と `handle_info/2` の `source` は変換前の params です。
  ハンドラーは対象 callback に適した戻り値（通常は `{:noreply, socket}`）を返す必要があります。

  `on_error:` を省略した場合、parse エラー時は `{:noreply, socket}` を返します。

  ## コンパイル時エラー

  `@params_schema` を対応外の関数、private 関数、または対応 callback でない arity に指定すると
  `ArgumentError` になります。変換対象の params を変数へ束縛していない場合、または
  `handle_info/2` の payload を `params` という変数名で束縛していない場合も `ArgumentError` になります。
  """

  @doc """
  callback の params 自動変換を有効にします。

  `on_error:` には、parse エラー時に呼び出す関数名を atom で指定します。関数は
  `handler(source, reason, socket)` の形で定義してください。
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
