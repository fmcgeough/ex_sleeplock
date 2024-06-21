# ExSleeplock

Allow concurrent throttling using a named lock in Elixir.

This project was inspired by the Erlang project [sleeplocks](https://hex.pm/packages/sleeplocks).
It provides similar functionality but adds:

- monitoring of processes that take locks
- dynamic supervision of the locks themselves
- telemetry event generation

Thanks to _Isaac Whitfield_ who created the Erlang sleeplocks library.

## What Does the Library Provide?

This library provides an app with the ability to create a named lock with a
value n (positive integer value) indicating the number of concurrent
processes. Only n processes can obtain the lock at any time. An executing
process is stored in a slot. When a lock is released the slot becomes available.

When no slots are available for a lock a process asking for that lock is
placed in a queue. The process execution is suspended until a slot is available.
As slots become available waiting processes are continued in a FIFO (first in
first out) manner.

## Telemetry

The library can be configured to generate telemetry. To do so setup your application
environment with:

```
:ex_sleeplock, notifier: ExSleeplock.EventGenerator.LockTelemetry
```

When this is setup three telemetry events are generated.

- `[:ex_sleeplock, :lock_created]` - generated when the lock is created
  - measurements - always `%{value: 1}`
  - metadata - `t:ExSleeplock.lock_info/0`
- `[:ex_sleeplock, :lock_acquired]` - generated when lock is acquired
  - measurements - `t:ExSleeplock.lock_state/0`
  - metadata - `t:ExSleeplock.lock_info/0`
- `[:ex_sleeplock, :lock_released]` - generated when lock is acquired
  - measurements - `t:ExSleeplock.lock_state/0`
  - metadata - `t:ExSleeplock.lock_info/0`

See the documentation for `ExSleeplock` for more information.

## Why would you need this?

The library is useful when you can have code within your app that must access a
resource that is limited in some way. You want only 2 or 3 (or some limited
number) of processes accessing the resource at the same time.

An example scenario is an app that connects to Kafka as a source of messages
that must be processed. Messages can arrive in parallel and are processed by
separate processes. The messages are processedc and stored in a relational
database. In addition, the app is also responsible for servicing an API. The API
reads / writes to the same relational database.

There are two issues in this scenario. One, there are a limited number of
connections to the database. You might get n incoming messages but have much
less than n connections available. Second, you don't want all your connections
used up to process incoming messages since your API could not respond in a timely
manner to incoming API requests.

## Simple Explanation of the Mechanics

```
ExSleeplock.new(:process_foo, _parallelism = 2)
```

This creates a lock called `:process_foo` with two slots. Only two processes
are allowed to execute concurrently. Using it from an app looks something
like this:

```
result = ExSleeplock.execute(:process_foo, fn -> some_work() end)
```

If there are already two processes with a `:process_foo` lock the third
process waits until one of the two currently running processes unlock.
Once a lock is released the waiting process starts immediately.

Using `ExSleeplock.execute/2` is the easiest way to use this library but you can
manage your own lock and timing of execution of a block of code using
`ExSleeplock.acquire/1` (blocking) or `ExSleeplock.attempt/1` (non-blocking). If you
are using the calls in this way then you are responsible for ensuring
`ExSleeplock.release/1` is called. Until `ExSleeplock.release/1` is called a slot is
being used and a new process may not be able to move forward.

When a lock is obtained by a process the library creates a monitor on the process
taking the lock. If the process exits unexpectedly the lock is automatically
released (even though the processs never called `ExSleeplock.release/1`).

## Brief API Overview

* `ExSleeplock.new/2` - create a sleep lock. Before a sleep lock can be used it
  has to be created. This is generally done when the application starts.
* `ExSleeplock.execute/2` - execute a function after acquiring a sleep lock
* `ExSleeplock.acquire/1` - acquire a sleep lock. Blocks until lock is acquired
* `ExSleeplock.attempt/1` - attempt to acquire a sleep lock. Doesn't block.
* `ExSleeplock.release/1` - release a sleep lock

## Trying It Out in iex

Start an iex session and paste the following module into the session.
The `process/3` function in the module simulates processing by sleeping
for 1 second plus some random number of milliseconds (< 100).

```
defmodule TestSleepwalk do
  def process(name, wait_time_in_ms, idx) do
    IO.puts("Queued  [#{idx}] at: #{current_time()}.")
    ExSleeplock.execute(name, fn ->
      # Simulate procesesing when a lock is obtained
      IO.puts("Lock    [#{idx}] at: #{current_time()}.")
      Process.sleep(wait_time_in_ms + :rand.uniform(100))
      IO.puts("Release [#{idx}] at: #{current_time()}.")
      idx
    end)
  end

  defp current_time do
    DateTime.utc_now() |> DateTime.truncate(:millisecond)
  end
end
```

Now create a lock called `:test_sleepwalk` that allows 2 concurrent processes.

```
iex> {:ok, pid} = ExSleeplock.new(:test_sleepwalk, 2)
```

Now let's start more than 2 processes using Task.async. All of the processes call
`TestSleepwalk.process/3`. An explanation of what happens is provided below.

```
iex> results = Enum.map(1..6, fn idx -> Task.async(fn -> TestSleepwalk.process(:test_sleepwalk, 1_000, idx) end) end) |> Task.await_many(10_000)

# All the tasks get queued. Before a call is done to obtain a lock the function outputs
# an index number. This means that all of this output happens first.

Queued  [1] at: 2024-06-12 16:22:43.072Z.
Queued  [2] at: 2024-06-12 16:22:43.072Z.
Queued  [3] at: 2024-06-12 16:22:43.072Z.
Queued  [4] at: 2024-06-12 16:22:43.072Z.
Queued  [5] at: 2024-06-12 16:22:43.072Z.
Queued  [6] at: 2024-06-12 16:22:43.072Z.

# Now the tasks attempt to obtain a lock and execute. Only two are
# allowed to obtain a lock. The rest are waiting.

Lock    [2] at: 2024-06-12 16:22:43.072Z.
Lock    [1] at: 2024-06-12 16:22:43.072Z.

# One of the two processes that started complete and release their lock
# This allows another process to get the lock and begin executing.

Release [1] at: 2024-06-12 16:22:44.102Z.
Lock    [3] at: 2024-06-12 16:22:44.103Z.

# Second task completes and the next waiting task locks and begins
# executing

Release [2] at: 2024-06-12 16:22:44.102Z.
Lock    [4] at: 2024-06-12 16:22:44.103Z.

# You should be able to see what is happening now. The remainder of
# the output is:

Release [3] at: 2024-06-12 16:22:45.152Z.
Lock    [5] at: 2024-06-12 16:22:45.153Z.
Release [4] at: 2024-06-12 16:22:45.188Z.
Lock    [6] at: 2024-06-12 16:22:45.190Z.
Release [5] at: 2024-06-12 16:22:46.202Z.
Release [6] at: 2024-06-12 16:22:46.246Z.
[1, 2, 3, 4, 5, 6]
```

If you use the pid acquired when creating the sleeplock you can see its current
state:

```
iex> :sys.get_state(pid)
%ExSleeplock.Slot{slots: 2, current: %{}, waiting: {[], []}}
```

## Other Notes

The only thing that you might not have seen if you've worked with Elixir/Phoenix
in standard web apps is using
[GenServer.reply/2](https://hexdocs.pm/elixir/GenServer.html#reply/2). This is a
feature of OTP that just doesn't come up that often. If `:noreply` is
returned from a handle_call then the calling process is suspended. Only when
someone (and it actually doesn't have to be the GenServer that got the original
`handle_call` calls `GenServer.reply` the result is returned to the
caller). By default, this would time-out but if you look at the `acquire`
function it passes `infinity` as the last argument. This means it waits until an
answer is available.
