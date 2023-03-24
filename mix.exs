defmodule OneAndDone.MixProject do
  use Mix.Project

  def project do
    [
      name: "One and Done",
      app: :one_and_done,
      version: "0.1.0",
      elixir: "~> 1.13",
      elixirc_paths: elixirc_paths(Mix.env()),
      package: package(),
      description: description(),
      source_url: "https://github.com/knocklabs/one-and-done",
      docs: [
        main: "README", # The main page in the docs
        extras: ["README.md"]
      ],
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:plug, "~> 1.14"},
      {:credo, "~> 1.4", only: [:dev, :test], runtime: false},
      {:mix_test_watch, "~> 1.0", only: :dev, runtime: false},
      {:ex_doc, "~> 0.29", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      name: "one_and_done",
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/knocklabs/one-and-done"}
    ]
  end

  defp description do
    """
    Easy to use plug for idempoent requests.
    """
  end
end
