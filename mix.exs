defmodule ExSleeplock.MixProject do
  @moduledoc false
  use Mix.Project

  @source_url "https://github.com/fmcgeough/ex_sleeplock"
  @version "0.10.0"

  def project do
    [
      app: :ex_sleeplock,
      version: @version,
      elixir: "~> 1.13",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "ex_sleeplock",
      source_url: @source_url,
      package: package(),
      docs: docs(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [coveralls: :test, "coveralls.html": :test, "coveralls.detail": :test]
    ]
  end

  def application do
    [
      mod: {ExSleeplock.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:telemetry, "~> 1.2"},
      {:mox, "~> 1.1", only: [:test]},
      {:credo, "~> 1.5", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.24", only: :dev, runtime: false},
      {:excoveralls, "~> 0.10", only: :test}
    ]
  end

  defp docs do
    [
      main: "readme",
      name: "ExSleeplock",
      source_ref: "v#{@version}",
      canonical: "http://hexdocs.pm/ex_sleeplock",
      source_url: @source_url,
      extras: ["README.md", "CHANGELOG.md": [title: "Changelog"], LICENSE: [title: "License"]]
    ]
  end

  defp package do
    [
      description: "Easy throttle of number of processes",
      maintainers: ["Frank McGeough"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end
end
