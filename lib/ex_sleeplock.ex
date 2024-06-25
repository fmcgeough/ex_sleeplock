defmodule ExSleeplock do
  @moduledoc """
  API allowing creation of locks to throttle concurrent processing via
  obtaining a lock before executing functionality you want to limit.

  Before a lock can be used it must be created using `new/2`. When `new/2`
  is called a process is created to manage the lock. The lock is identified
  by a unique atom and the number of slots indicates how many processes can
  hold the lock at once. The name of the lock is the process name.

  The preferred way to use a created lock is with the function `execute/2`.
  This function acquires the lock, executes the function passed in and
  then releases the lock (returning the function return value to the caller)
  This ensures that the lock is always released even if an exception is raised.
  """
  @help "Sleep locks must have a unique name indicated by an atom and slots must be a positive integer"

  @typedoc """
  General information about a lock
  """
  @type lock_info :: %{
          name: atom(),
          num_slots: pos_integer()
        }

  @typedoc """
  Number of processes that have obtained the lock and are currently running and
  the number of processes waiting for a lock
  """
  @type lock_state :: %{
          running: non_neg_integer(),
          waiting: non_neg_integer()
        }

  @doc """
  Create a sleep lock

  ## Arguments

  * name - a unique atom identifying the sleep lock. The name becomes the process name
    for the lock
  * num_slots - a positive integer indicating how many processes are allowed to hold
    this sleep lock at once

  ## Returns

  * `{:ok, pid}` - on success a GenServer using the name supplied is started. This
     process is supervised by the library.
  * `{:error, :invalid, msg}` - returned when parameters are invalid
  * `{:error, {:already_started, pid}}` - returned when attempting to create the same
    lock more than once
  """
  @spec new(atom(), pos_integer()) ::
          {:ok, pid()} | {:error, :invalid, String.t()} | {:error, {:already_started, pid}}
  def new(name, num_slots) when is_atom(name) and is_integer(num_slots) and num_slots > 0 do
    ExSleeplock.LockSupervisor.start_lock(%{name: name, num_slots: num_slots})
  end

  def new(_name, _num_slots) do
    {:error, :invalid, @help}
  end

  @doc """
  Aquire a sleep lock

  This will block until a lock can be acquired. When a sleep lock is
  acquired the caller is responsible for calling `release/1`.

  ## Arguments

  * name - a unique atom identifying the sleep lock

  ## Returns

  * `:ok` - after lock is acquired
  * `{:error, :sleeplock_not_found}` - if called with a name that doesn't match
    an existing sleeplock
  """
  @spec acquire(atom()) :: :ok | {:error, :sleeplock_not_found}
  def acquire(name) when is_atom(name) do
    GenServer.call(name, :acquire, :infinity)
  catch
    :exit, _ -> {:error, :sleeplock_not_found}
  end

  @doc """
  Execute the function passed in by first acquiring the lock

  The lock is automatically released when the function completes. This call
  blocks until a lock is acquired.

  ## Arguments

  * name - a unique atom identifying the sleep lock
  * fun - a function that executes after the sleep lock is acquired

  ## Returns

  * on success the call returns the value returned by the function supplied
  * `{:error, :sleeplock_not_found}` - if called with a name that doesn't match
    an existing sleeplock
  """
  @spec execute(atom(), (-> any())) :: any() | {:error, :sleeplock_not_found}
  def execute(name, fun) when is_atom(name) do
    case acquire(name) do
      :ok -> fun.()
      err -> err
    end
  after
    release(name)
  end

  @doc """
  Release an acquired lock

  ## Arguments

  * name - a unique atom identifying the sleep lock

  ## Returns

  * `:ok` - always returned even if you do not have an acquired lock
  * `{:error, :sleeplock_not_found}` - if called with a name that doesn't match
    an existing sleeplock
  """
  @spec release(atom()) :: :ok | {:error, :sleeplock_not_found}
  def release(name) when is_atom(name) do
    GenServer.call(name, :release)
  catch
    :exit, _ -> {:error, :sleeplock_not_found}
  end

  @doc """
  A non-blocking version of `acquire/1`

  ## Arguments

  * name - a unique atom identifying the sleep lock

  ## Returns

  * `:ok` - lock is acquired
  * `{:error, :unavailable}` - lock is not acquired
  * `{:error, :sleeplock_not_found}` - if called with a name that doesn't match
    an existing sleeplock
  """
  @spec attempt(atom()) :: :ok | {:error, :unavailable} | {:error, :sleeplock_not_found}
  def attempt(name) when is_atom(name) do
    GenServer.call(name, :attempt)
  catch
    :exit, _ -> {:error, :sleeplock_not_found}
  end

  @doc """
  Return the current state of a sleep lock
  """
  @spec lock_state(atom()) :: {:ok, lock_state()} | {:error, :sleeplock_not_found}
  def lock_state(name) when is_atom(name) do
    GenServer.call(name, :lock_state)
  catch
    :exit, _ -> {:error, :sleeplock_not_found}
  end

  @doc """
  Return help on creating a sleep lock
  """
  def help do
    @help
  end
end
