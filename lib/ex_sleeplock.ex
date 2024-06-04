defmodule ExSleeplock do
  @moduledoc """
  Allow creation of locks that can be acquired and released in a manner
  similar to spinlocks but with the ability to throttle the number of
  processes that can acquire the lock at once.

  This is an Elixir implementation fo an existing library called `sleeplocks`.
  It was ported to Elixir to allow for better integration with Elixir and
  to implement a supervisor for the locks so that they can be restarted
  when necessary.

  Sleep locks allow an app to throttle the number of processes that are allowed
  to be executing some section of code at any one time. It does this by creating
  the number of slots that the caller requested and only allowing that number of
  processes to get the lock at any one time.

  A good example of when this is needed is when an app connects to Kafka via
  `brod` and subscribes to a topic. Since `brod` is starting its own processes
  to handle messages and doing calls back into the app, the app may be
  overwhelmed with calls from brod. This is especially concerning if the app
  tries to use a limited resource on the callback (like doing some database
  activity).

  Usage is fairly straightforward. Let's assume that you have a subscriber
  callback for `brod` that ends up calling a function: `process_foo(msg)`
  and you only want to allow 2 of those calls to be executing simulatenously.
  When the app starts up you create a Sleeplock by:

  ```
  parallelism = 2
  :ok = Sleeplock.new(:process_foo, parallelism)
  ```

  This creates the sleep lock with two slots. Only two processes are allowed to
  execute at one time. Now change the call to:

  ```
  Sleeplock.execute(:process_foo, fn -> process_foo(msg) end)
  ```

  If there are already two processes executing `process_foo/1` then the third call
  waits until one of the two currently running completes. Once a currently
  executing call completes the waiting process starts immediately.

  Using `Sleeplock.execute/2` is the easiest way to use this library.
  You can manage your own lock and timing of execution of a block of code
  using `acquire/1` (blocking) or `attempt/1` (non-blocking). If you are
  using those functions then you are responsible for ensuring `release/1`
  is called. Until `release/1` is called a slot is being used and a new
  process may not be able to move forward.

  When a lock is created the sleep lock code creates a monitor on the process
  taking the lock. If the process exits unexpectedly the lock is automatically
  released (even though the processs never called `release/1`).
  """
  use GenServer

  @help "Sleep locks must have a unique name indicated by an atom and slots must be a positive integer"

  alias ExSleeplock.Slot

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
  def acquire(name) do
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
  def execute(name, fun) do
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
  def release(name) do
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
  def attempt(name) do
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
