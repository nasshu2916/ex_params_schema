defmodule ExParamsSchema.Definition.TypespecTest do
  use ExUnit.Case, async: true

  doctest ExParamsSchema.Definition.Typespec

  alias ExParamsSchema.Definition.{Field, Typespec}

  defmodule PriceType do
    @behaviour ExParamsSchema.Type

    @type t :: %{cents: non_neg_integer()}

    @impl true
    def cast(value, _options), do: {:ok, value}

    @impl true
    def to_json(value, _options), do: value

    @impl true
    def json_schema(_options), do: %{"type" => "integer"}
  end

  defmodule SlugType do
    @behaviour ExParamsSchema.Type

    @type t :: String.t()

    @impl true
    def cast(value, _options), do: {:ok, value}

    @impl true
    def to_json(value, _options), do: value

    @impl true
    def json_schema(_options), do: %{"type" => "string"}

    @impl true
    def typespec, do: quote(do: String.t())
  end

  defmodule StructWithoutType do
    @behaviour ExParamsSchema.Type

    defstruct [:value]

    @impl true
    def cast(value, _options), do: {:ok, %__MODULE__{value: value}}

    @impl true
    def to_json(%__MODULE__{value: value}, _options), do: value

    @impl true
    def json_schema(_options), do: %{"type" => "string"}
  end

  test "フィールドから構造体型の型仕様 AST を生成する" do
    type =
      [
        {:any_value, :any, []},
        {:boolean_value, :boolean, []},
        {:integer_value, :integer, []},
        {:float_value, :float, []},
        {:number_value, :number, []},
        {:date_value, :date, []},
        {:datetime_value, :datetime, []},
        {:null_value, :null, []},
        {:enum_value, {:enum, [:merge, :replace]}, []},
        {:custom_value, {PriceType, []}, []},
        {:primitive_custom_value, {SlugType, []}, []},
        {:optional_string, :string, [optional: true]},
        {:integer_list, [:integer], []},
        {:nonempty_integer_list, [:integer], [min_items: 1]},
        {:optional_nullable_string_list, [{:string, nullable: true}], [optional: true]},
        {
          :nullable_object_value,
          %{
            x: :integer,
            label: {:string, optional: true},
            tags: [{:string, nullable: true}],
            nested_object: %{active: :boolean}
          },
          [nullable: true]
        }
      ]
      |> ExParamsSchema.Definition.compile_fields!()
      |> Typespec.struct_type()
      |> Macro.to_string()

    assert type =~ "any_value: dynamic()"
    assert type =~ "boolean_value: boolean()"
    assert type =~ "integer_value: integer()"
    assert type =~ "float_value: float()"
    assert type =~ "number_value: number()"
    assert type =~ "date_value: Date.t()"
    assert type =~ "datetime_value: DateTime.t()"
    assert type =~ "null_value: nil"
    assert type =~ "enum_value: :replace | :merge"
    assert type =~ "custom_value: dynamic()"
    assert type =~ "primitive_custom_value: String.t()"
    assert type =~ "optional_string: String.t() | nil"
    assert type =~ "integer_list: [integer()]"
    assert type =~ "nonempty_integer_list: [integer(), ...]"
    assert type =~ "optional_nullable_string_list: [String.t() | nil] | nil"

    assert type =~
             "nullable_object_value:\n    %{\n      label: String.t() | nil,\n      x: integer(),\n      tags: [String.t() | nil],\n      nested_object: %{active: boolean()}\n    }\n    | nil\n}"

    fields = [
      %Field{name: :enum_value, type: {:enum, [:draft, :published]}},
      %Field{
        name: :object_value,
        type:
          {:array,
           {:object,
            [
              %Field{name: :id, type: :integer},
              %Field{name: :name, type: :string, options: [optional: true]}
            ]}, []},
        options: [min_items: 1]
      }
    ]

    assert fields
           |> Typespec.struct_type()
           |> Macro.to_string() ==
             "%__MODULE__{\n  enum_value: :published | :draft,\n  object_value: [%{id: integer(), name: String.t() | nil}, ...]\n}"
  end

  test "struct の t/0 だけをカスタム型として参照する" do
    assert "%__MODULE__{struct_custom_value: ExParamsSchema.ValidationError.t()}" ==
             [%Field{name: :struct_custom_value, type: {:custom, ExParamsSchema.ValidationError, []}}]
             |> Typespec.struct_type()
             |> Macro.to_string()

    assert "%__MODULE__{struct_without_type_value: dynamic()}" ==
             [%Field{name: :struct_without_type_value, type: {:custom, StructWithoutType, []}}]
             |> Typespec.struct_type()
             |> Macro.to_string()
  end
end
