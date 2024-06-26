defmodule ExSleeplock.Lock do
  @moduledoc false

  use GenServer

  alias ExSleeplock.Slot

  def start_link(%{num_slots: num_slots, name: name}) do
    slot_record = Slot.new(name, num_slots)
    GenServer.start_link(__MODULE__, slot_record, name: name)
  end

  @impl true
  def init(state) do
    Slot.generate_event(:lock_created, state)
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
        new_state = %{state | waiting: updated_queue}
        Slot.generate_event(:lock_waiting, new_state)
        {:noreply, new_state}
    end
  end

  def handle_call(:release, {from, _ref}, %{current: current} = state) do
    new_state =
      case Map.get(current, from) do
        nil ->
          state

        monitor ->
          new_current = Map.delete(current, from)
          Process.demonitor(monitor)
          next_caller(%{state | current: new_current})
      end

    {:reply, :ok, new_state}
  end

  def handle_call(:attempt, from, state) do
    case try_lock(from, state) do
      {:ok, state} ->
        {:reply, :ok, state}

      {:error, :unavailable} = err ->
        {:reply, err, state}
    end
  end

  def handle_call(:lock_state, _from, state) do
    {:reply, Slot.lock_state(state), state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, %{current: current} = state) do
    new_current = Map.delete(current, pid)
    new_state = next_caller(%{state | current: new_current})
    {:noreply, new_state}
  end

  defp try_lock(from, %{num_slots: num_slots, current: current} = state) do
    if already_locked?(from, current) do
      {:ok, state}
    else
      case Enum.count(current) do
        num_current when num_current == num_slots ->
          {:error, :unavailable}

        _ ->
          {:ok, lock_caller(from, state)}
      end
    end
  end

  defp lock_caller({from, _ref}, %{current: current} = state) do
    monitor = Process.monitor(from)
    new_current = Map.put(current, from, monitor)
    new_state = %{state | current: new_current}

    Slot.generate_event(:lock_acquired, new_state)

    new_state
  end

  defp next_caller(%{waiting: waiting} = state) do
    case :queue.out(waiting) do
      {:empty, _} ->
        Slot.generate_event(:lock_released, state)
        state

      {{:value, next}, new_waiting} ->
        new_state = %{state | waiting: new_waiting}
        Slot.generate_event(:lock_released, new_state)
        GenServer.reply(next, :ok)
        lock_caller(next, new_state)
    end
  end

  defp already_locked?({from, _ref}, current) do
    Map.has_key?(current, from)
  end
end
