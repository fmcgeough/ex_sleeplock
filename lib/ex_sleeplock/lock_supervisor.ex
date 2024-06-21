defmodule ExSleeplock.LockSupervisor do
  @moduledoc false

  use DynamicSupervisor

  alias ExSleeplock.EventGenerator

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
    lock_info = %{name: name, num_slots: num_slots}

    child_spec = %{
      id: ExSleeplock,
      start: {ExSleeplock.Lock, :start_link, [lock_info]},
      restart: :permanent,
      type: :worker
    }

    result = DynamicSupervisor.start_child(__MODULE__, child_spec)
    log_result(result, lock_info)
    result
  end

  defp log_result({:ok, _}, lock_info) do
    EventGenerator.lock_created(lock_info)
  end

  defp log_result(result, lock_info) do
    Logger.error("Unable to start lock #{inspect(lock_info)}, error: #{inspect(result)}")
  end
end
