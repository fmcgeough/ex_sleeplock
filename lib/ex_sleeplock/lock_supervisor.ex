defmodule ExSleeplock.LockSupervisor do
  @moduledoc """
  Provide a Dynamic supervisor for our locks so that they are restarted
  when necessary
  """
  use DynamicSupervisor

  require Logger

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_lock(name, num_slots) do
    child_spec = %{
      id: ExSleeplock,
      start: {ExSleeplock, :start_link, [%{name: name, num_slots: num_slots}]},
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
