defmodule Mix.Tasks.ExParamsSchema.GenerateSchema do
  @shortdoc "Generates a defschema module from JSON Schema"

  @moduledoc """
  Generates an `ExParamsSchema` module from a JSON Schema Draft 7 object schema.

      mix ex_params_schema.generate_schema priv/schemas/create_user.json MyAppWeb.Params.CreateUser
      mix ex_params_schema.generate_schema priv/schemas/create_user.json MyAppWeb.Params.CreateUser --output lib/my_app_web/params/create_user.ex

  Without `--output`, generated Elixir source is written to standard output.
  """

  use Mix.Task

  alias ExParamsSchema.JsonSchema.ModuleGenerator

  @switches [output: :string]

  @impl Mix.Task
  def run(args) do
    {options, arguments, invalid} = OptionParser.parse(args, strict: @switches)
    validate_arguments!(arguments, invalid)
    [input_path, module_name] = arguments

    source = input_path |> read_schema!() |> ModuleGenerator.generate!(module_name)
    write_source(source, options[:output])
  end

  defp validate_arguments!([_input_path, _module_name], []), do: :ok

  defp validate_arguments!(_arguments, _invalid) do
    Mix.raise("usage: mix ex_params_schema.generate_schema SCHEMA_PATH MODULE [--output PATH]")
  end

  defp read_schema!(input_path) do
    case File.read(input_path) do
      {:ok, contents} -> Jason.decode!(contents)
      {:error, reason} -> Mix.raise("could not read JSON Schema #{input_path}: #{:file.format_error(reason)}")
    end
  rescue
    error in Jason.DecodeError -> Mix.raise("could not parse JSON Schema #{input_path}: #{Exception.message(error)}")
  end

  defp write_source(source, nil), do: Mix.shell().info(source)

  defp write_source(source, output_path) do
    output_path |> Path.dirname() |> File.mkdir_p!()
    File.write!(output_path, source)
    Mix.shell().info("Wrote ExParamsSchema module to #{output_path}")
  end
end
