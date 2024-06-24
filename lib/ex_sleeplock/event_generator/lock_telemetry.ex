defmodule ExSleeplock.EventGenerator.LockTelemetry do
  @moduledoc false

  @behaviour ExSleeplock.EventGenerator

  @events [
    [:ex_sleeplock, :lock_created],
    [:ex_sleeplock, :lock_acquired],
    [:ex_sleeplock, :lock_released],
    [:ex_sleeplock, :lock_waiting]
  ]

  @doc """
  Return the list of telemetry events that can be generated
  """
  def events, do: @events

  @impl true
  def lock_created(lock_info) do
    :telemetry.execute([:ex_sleeplock, :lock_created], %{value: 1}, lock_info)
  end

  @impl true
  def lock_acquired(lock_info, lock_state) do
    :telemetry.execute([:ex_sleeplock, :lock_acquired], lock_state, lock_info)
  end

  @impl true
  def lock_released(lock_info, lock_state) do
    :telemetry.execute([:ex_sleeplock, :lock_released], lock_state, lock_info)
  end

  @impl true
  def lock_waiting(lock_info, lock_state) do
    :telemetry.execute([:ex_sleeplock, :lock_waiting], lock_state, lock_info)
  end
end
