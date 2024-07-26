defmodule ExSleeplock.MixProject do
  @moduledoc false
  use Mix.Project

  def project do
    [
      app: :ex_sleeplock,
      version: "0.10.0",
      elixir: "~> 1.13",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "ex_sleeplock",
      source_url: "https://github.com/fmcgeough/ex_sleeplock",
      package: package(),
      docs: [
        main: "readme",
        extras: ["README.md", "CHANGELOG.md": [title: "Changelog"]],
        language: "en"
      ],
      test_coverage: [
        tool: ExCoveralls
      ],
      preferred_cli_env:
        cli_env_for(:test, [
          "coveralls",
          "coveralls.detail",
          "coveralls.html"
        ])
    ]
  end

  defp cli_env_for(env, tasks) do
    Enum.reduce(tasks, [], fn key, acc -> Keyword.put(acc, :"#{key}", env) end)
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

  defp package do
    [
      description: "Easy throttle of number of processes",
      maintainers: ["Frank McGeough"],
      licenses: ["MIT"],
      links: %{github: "https://github.com/PagerDuty/sleeplock"}
    ]
  end
end
