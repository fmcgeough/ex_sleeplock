defmodule ExSleeplock.EventGenerator.NoOp do
  @moduledoc false

  @behaviour ExSleeplock.EventGenerator

  @impl true
  def lock_created(_lock_info), do: :ok

  @impl true
  def lock_acquired(_lock_info, _lock_state), do: :ok

  @impl true
  def lock_released(_lock_info, _lock_state), do: :ok

  @impl true
  def lock_waiting(_lock_info, _lock_state), do: :ok
end
