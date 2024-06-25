defmodule ExSleeplock.StartupLocks do
  @moduledoc false

  use GenServer

  alias ExSleeplock.LockSupervisor

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end

  @impl true
  def init(_opts) do
    Enum.each(configured_locks(), &LockSupervisor.start_lock/1)

    {:ok, %{}}
  end

  def configured_locks do
    :ex_sleeplock
    |> Application.get_env(:locks, [])
    |> validate_locks()
  end

  defp validate_locks(locks) when is_list(locks) do
    Enum.filter(locks, &LockSupervisor.valid_lock?/1)
  end

  defp validate_locks(_), do: []
end
