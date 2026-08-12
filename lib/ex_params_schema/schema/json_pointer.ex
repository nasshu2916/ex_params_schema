defmodule ExParamsSchema.Schema.JsonPointer do
  @moduledoc """
  Provides pure functions for converting and matching JSON Pointers and field paths.

  JSON Schema validation errors use JSON Pointers, while the application uses paths made of
  string keys and list indexes. This module centralizes the conversion rules.
  """

  @type segment :: String.t()
  @type resolved_segment :: String.t() | non_neg_integer()
  @type pattern_segment :: String.t() | :index
  @type pattern :: [pattern_segment()]
  @type pointer_path :: [segment()]
  @type resolved_path :: [resolved_segment()]

  @doc """
  Decodes a JSON Pointer into unresolved segments.

      iex> ExParamsSchema.Schema.JsonPointer.decode("#/a~1b~0c/0")
      {:ok, ["a/b~c", "0"]}
  """
  @spec decode(String.t()) :: {:ok, pointer_path()} | :error
  def decode("#"), do: {:ok, []}

  def decode("#/" <> pointer) do
    pointer
    |> String.split("/", trim: false)
    |> Enum.map(&unescape_segment/1)
    |> then(&{:ok, &1})
  end

  def decode(_pointer), do: :error

  @doc """
  Parses a JSON Pointer into a path of string keys and list indices.

      iex> ExParamsSchema.Schema.JsonPointer.parse("#/entries/0/value")
      ["entries", 0, "value"]

  `#` represents the root. Invalid pointers are treated as an empty path.
  """
  @spec parse(String.t()) :: resolved_path()
  def parse(pointer) do
    case decode(pointer) do
      {:ok, path} -> resolve_segments(path)
      :error -> []
    end
  end

  @doc """
  Converts list indices in a JSON Pointer path to integers.
  """
  @spec resolve_segments(pointer_path()) :: resolved_path()
  def resolve_segments(path), do: Enum.map(path, &resolve_segment/1)

  @doc """
  Returns the resolved path when a definition pattern matches the beginning of a path.

  `:index` matches only segments that are non-negative integers.
  """
  @spec match(pattern(), pointer_path()) :: {:ok, resolved_path()} | :error
  def match(pattern, path) do
    case resolve_pattern(pattern, path) do
      {:ok, resolved, trailing} -> {:ok, resolved ++ resolve_segments(trailing)}
      _other -> :error
    end
  end

  @doc """
  Escapes a JSON Pointer segment according to RFC 6901.
  """
  @spec escape_segment(String.t()) :: String.t()
  def escape_segment(segment) when is_binary(segment) do
    segment |> String.replace("~", "~0") |> String.replace("/", "~1")
  end

  @spec resolve_pattern(pattern(), pointer_path()) ::
          {:ok, resolved_path(), pointer_path()} | :error
  defp resolve_pattern(pattern, path), do: resolve_pattern(pattern, path, [])

  @spec resolve_pattern(pattern(), pointer_path(), resolved_path()) ::
          {:ok, resolved_path(), pointer_path()} | :error
  defp resolve_pattern([], path, resolved), do: {:ok, Enum.reverse(resolved), path}

  defp resolve_pattern([:index | pattern], [segment | path], resolved) do
    case index_segment(segment) do
      {:ok, index} -> resolve_pattern(pattern, path, [index | resolved])
      :error -> :error
    end
  end

  defp resolve_pattern([:index | _pattern], [], _resolved), do: :error

  defp resolve_pattern([segment | pattern], path, resolved) do
    case consume_segment(segment, path) do
      {:ok, remaining} -> resolve_pattern(pattern, remaining, [segment | resolved])
      :error -> :error
    end
  end

  defp resolve_pattern(_pattern, _path, _resolved), do: :error
  @spec consume_segment(segment(), pointer_path()) :: {:ok, pointer_path()} | :error
  defp consume_segment(expected, [actual | path]) when expected == actual, do: {:ok, path}

  defp consume_segment(segment, path) do
    raw_segments = String.split(segment, "/")

    if length(raw_segments) > 1 and Enum.take(path, length(raw_segments)) == raw_segments do
      {:ok, Enum.drop(path, length(raw_segments))}
    else
      :error
    end
  end

  @spec resolve_segment(segment()) :: resolved_segment()
  defp resolve_segment(segment) do
    case index_segment(segment) do
      {:ok, index} -> index
      :error -> segment
    end
  end

  @spec index_segment(segment()) :: {:ok, non_neg_integer()} | :error
  defp index_segment("0"), do: {:ok, 0}

  defp index_segment(<<first, _rest::binary>> = segment) when first in ?1..?9 do
    case Integer.parse(segment) do
      {index, ""} -> {:ok, index}
      _other -> :error
    end
  end

  defp index_segment(_segment), do: :error

  @spec unescape_segment(segment()) :: segment()
  defp unescape_segment(segment) do
    segment |> String.replace("~1", "/") |> String.replace("~0", "~")
  end
end
