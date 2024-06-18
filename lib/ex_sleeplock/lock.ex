defmodule ExSleeplock.Lock do
  @moduledoc false

  use GenServer

  alias ExSleeplock.Slot

  def start_link(%{num_slots: num_slots, name: name}) do
    slot_record = Slot.new(num_slots)
    GenServer.start_link(__MODULE__, slot_record, name: name)
  end

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_call(:acquire, from, %{waiting: waiting} = state) do
    case try_lock(from, state) do
      {:ok, state} ->
        {:reply, :ok, state}

      {:error, :unavailable} ->
        # No slots available, add to our waiting queue and send back `:noreply`
        # This continues the loop with our updated state. Only when a lock is
        # released will we use the call `GenServer.reply(next, :ok)` to let this
        # blocked process that requested lock move forward.
        updated_queue = :queue.snoc(waiting, from)
        {:noreply, %{state | waiting: updated_queue}}
    end
  end

  @impl true
  def handle_call(:release, {from, _ref}, %{current: current} = lock) do
    new_lock =
      case Map.get(current, from) do
        nil ->
          lock

        monitor ->
          new_current = Map.delete(current, from)
          Process.demonitor(monitor)
          next_caller(%{lock | current: new_current})
      end

    {:reply, :ok, new_lock}
  end

  @impl true
  def handle_call(:attempt, from, state) do
    case try_lock(from, state) do
      {:ok, state} ->
        {:reply, :ok, state}

      {:error, :unavailable} = err ->
        {:reply, err, state}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, %{current: current} = state) do
    {:noreply, %{state | current: Map.delete(current, pid)}}
  end

  defp try_lock(from, %{slots: num_slots, current: current} = state) do
    case Enum.count(current) do
      num_current when num_current == num_slots ->
        {:error, :unavailable}

      _ ->
        {:ok, lock_caller(from, state)}
    end
  end

  defp lock_caller({from, _ref}, %{current: current} = state) do
    monitor = Process.monitor(from)
    %{state | current: Map.put(current, from, monitor)}
  end

  defp next_caller(%{waiting: waiting} = lock) do
    case :queue.out(waiting) do
      {:empty, _} ->
        lock

      {{:value, next}, new_waiting} ->
        GenServer.reply(next, :ok)
        new_lock = lock_caller(next, lock)
        %{new_lock | waiting: new_waiting}
    end
  end
end
