defmodule ExSleeplock.EventGenerator do
  @moduledoc false

  # Define a beehaviour to allow event generation when a lock is acquired or released

  @lock_notifier Application.compile_env(
                   :ex_sleeplock,
                   :notifier,
                   ExSleeplock.EventGenerator.NoOp
                 )

  @type lock_info :: ExSleeplock.lock_info()
  @type lock_state :: ExSleeplock.lock_state()

  @doc """
  Called when a lock is created
  """
  @callback lock_created(lock_info()) :: any

  @doc """
  Called when a lock is acquired. Provides information on the number of processes currently running
  in parallel and the number of processes waiting for a lock.
  """
  @callback lock_acquired(lock_info(), lock_state()) :: any

  @doc """
  Called when a lock is released.  Provides information on the number of processes currently running
  in parallel and the number of processes waiting for a lock.
  """
  @callback lock_released(lock_info(), lock_state()) :: any

  @doc """
  Called when a process is added to queue to wait for a lock
  """
  @callback lock_waiting(lock_info(), lock_state()) :: any

  def lock_created(lock_info) do
    @lock_notifier.lock_created(lock_info)
  end

  def lock_acquired(lock_info, lock_state) do
    @lock_notifier.lock_acquired(lock_info, lock_state)
  end

  def lock_released(lock_info, lock_state) do
    @lock_notifier.lock_released(lock_info, lock_state)
  end

  def lock_waiting(lock_info, lock_state) do
    @lock_notifier.lock_waiting(lock_info, lock_state)
  end
end
