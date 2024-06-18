defmodule ExSleeplock.LockSupervisor do
  @moduledoc false

  use DynamicSupervisor

  require Logger

  @doc """
  Called when library is loaded to start the supervisor
  """
  def start_link(_arg) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Start a child sleep lock process
  """
  def start_lock(name, num_slots) when is_integer(num_slots) and num_slots > 0 do
    child_spec = %{
      id: ExSleeplock,
      start: {ExSleeplock.Lock, :start_link, [%{name: name, num_slots: num_slots}]},
      restart: :permanent,
      type: :worker
    }

    lock_description = lock_description(name, num_slots)
    result = DynamicSupervisor.start_child(__MODULE__, child_spec)
    log_result(result, lock_description)
    result
  end

  defp log_result({:ok, _}, lock_description) do
    Logger.info("Starting #{lock_description}")
  end

  defp log_result(result, lock_description) do
    Logger.error("Unable to start #{lock_description}, error: #{inspect(result)}")
  end

  defp lock_description(name, num_slots) do
    "lock #{name}, num_slots: #{num_slots}"
  end
end
