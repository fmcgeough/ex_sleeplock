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
  Check for valid lock info
  """
  def valid_lock?(%{name: name, num_slots: num_slots}) do
    is_atom(name) and is_integer(num_slots) and num_slots > 0
  end

  def valid_lock?(_lock_info), do: false

  @doc """
  Return a child spec to start a new lock process
  """
  def lock_child_spec(lock_info) do
    if valid_lock?(lock_info) do
      %{
        id: ExSleeplock,
        start: {ExSleeplock.Lock, :start_link, [lock_info]},
        restart: :permanent,
        type: :worker
      }
    else
      raise ArgumentError, "Invalid lock info: #{inspect(lock_info)}"
    end
  end

  @doc """
  Start a child sleep lock process
  """
  def start_lock(lock_info) do
    child_spec = lock_child_spec(lock_info)
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
