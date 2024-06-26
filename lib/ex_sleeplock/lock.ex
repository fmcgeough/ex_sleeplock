defmodule ExSleeplock.Lock do
  @moduledoc false

  use GenServer

  alias ExSleeplock.Slot

  def start_link(%{num_slots: num_slots, name: name}) do
    state = Slot.new(name, num_slots)
    GenServer.start_link(__MODULE__, state, name: name)
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

  def handle_call(:release, {pid, _ref}, state) do
    new_state = release_lock(pid, state)

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
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    new_state = release_lock(pid, state)
    {:noreply, new_state}
  end

  defp try_lock({pid, _ref}, state) do
    if already_locked?(pid, state) do
      {:ok, state}
    else
      case slot_available?(state) do
        true -> {:ok, lock(pid, state)}
        false -> {:error, :unavailable}
      end
    end
  end

  defp lock(pid, %{current: current} = state) do
    monitor = Process.monitor(pid)
    new_current = Map.put(current, pid, monitor)
    new_state = %{state | current: new_current}
    Slot.generate_event(:lock_acquired, new_state)

    new_state
  end

  defp release_lock(pid, %{current: current} = state) do
    case Map.get(current, pid) do
      nil ->
        state

      monitor ->
        Process.demonitor(monitor)
        new_current = Map.delete(current, pid)
        new_state = %{state | current: new_current}
        Slot.generate_event(:lock_released, new_state)
        next_caller(new_state)
    end
  end

  defp next_caller(%{waiting: waiting} = state) do
    case :queue.out(waiting) do
      {:empty, _} ->
        state

      {{:value, {pid, _} = next}, new_waiting} ->
        new_state = %{state | waiting: new_waiting}
        GenServer.reply(next, :ok)
        lock(pid, new_state)
    end
  end

  defp already_locked?(pid, %{current: current}) do
    Map.has_key?(current, pid)
  end

  defp slot_available?(%{num_slots: num_slots, current: current}) do
    Enum.count(current) < num_slots
  end
end
