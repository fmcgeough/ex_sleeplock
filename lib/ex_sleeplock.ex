defmodule ExSleeplock do
  @moduledoc """
  API allowing creation of locks to throttle concurrent processing via
  obtaining a lock before executing functionality you want to limit.

  This is an Elixir implementation based on an existing Erlang library
  integration with Elixir and to implement a supervisor for the locks
  so that they can be restarted when necessary.

  Before a lock can be used it must be created using `new/2`. The
  preferred way to use a created lock is with the function `execute/2`.
  This function acquires the lock, executes the function passed in and
  then releases the lock. This ensures that the lock is always released
  even if an exception is raised.
  """
  @help "Sleep locks must have a unique name indicated by an atom and slots must be a positive integer"

  @doc """
  Create a sleep lock

  ## Arguments

  * name - a unique atom identifying the sleep lock
  * num_slots - a positive integer indicating how many processes are allowed to hold
    this sleep lock at once

  ## Returns

  * `{:ok, pid}` - on success the sleep lock codes starts a GenServer using the
    name supplied
  * `{:error, :invalid, msg}` - if the parameters are invalid then you'll get
    back this
  * `{:error, {:already_started, pid}}` - if you attempt to call new twice with
    the same name then you'll get this error
  """
  @spec new(atom(), pos_integer()) ::
          {:ok, pid()} | {:error, :invalid, String.t()} | {:error, {:already_started, pid}}
  def new(name, num_slots) when is_atom(name) and is_integer(num_slots) and num_slots > 0 do
    ExSleeplock.LockSupervisor.start_lock(name, num_slots)
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
  @spec execute(atom(), nil) :: any() | {:error, :sleeplock_not_found}
  def execute(name, fun) when is_atom(name) do
    case acquire(name) do
      :ok -> fun.()
      err -> err
    end
  after
    release(name)
  catch
    :exit, _ -> {:error, :sleeplock_not_found}
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
  Return help on creating a sleep lock
  """
  def help do
    @help
  end
end
