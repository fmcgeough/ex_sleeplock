defmodule ExSleeplock.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_sleeplock,
      version: "1.0.0",
      elixir: "~> 1.13",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "ex_sleeplock",
      source_url: "https://github.com/fmcgeough/ex_sleeplock",
      package: package(),
      docs: [
        main: "readme",
        extras: ["README.md"],
        language: "en"
      ],
      test_coverage: [
        tool: ExCoveralls
      ],
      preferred_cli_env: [coveralls: :test, "coveralls.html": :test]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {ExSleeplock.Application, []},
      extra_applications: [:logger]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
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
