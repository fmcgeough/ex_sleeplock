# ExSleeplock

An easy approach to throttling the number of processes allowed to execute a
block of code simultaneously in Elixir.

Started from the Erlang project `https://hex.pm/packages/sleeplocks` with added
monitoring of processes that take locks and dynamic supervision of the locks
themselves. Thanks to Isaac Whitfield who created the sleeplocks library.

## Details

This library provides an app with the ability to use sleep locks. So what are
sleep locks?

Sleep locks allow an app to throttle the number of processes that are allowed
to be executing some section of code at any one time. It does this by creating
the number of slots that the caller requested and only allowing that number of
processes to get the lock at any one time.

A good example of when this is needed is when an app connects to Kafka via
`brod` and subscribes to a topic. Since `brod` is starting its own processes to
handle data from Kafka and executing a callback that the app provides, the app
may be overwhelmed with calls from brod. This is especially concerning if the
app tries to use a limited resource during the callback. For example, using a
database connection.

Usage is fairly straightforward. Let's assume that you have a subscriber
callback for `brod` that ends up calling a function: `process_foo(msg)`
and you only want to allow two of those calls to be executing simultaneously.
When the app starts up you create a Sleeplock by:

```
parallelism = 2
:ok = ExSleeplock.new(:process_foo, parallelism)
```

This creates the sleep lock with two slots. Only two processes are allowed to
execute at one time. Now change the call to:

```
sync_fun = fn -> process_foo(msg) end
ExSleeplock.execute(:process_foo, sync_fun)
```

If there are already two processes executing `process_foo/1` then the third call
waits until one of the two currently running completes. Once a currently
executing call completes the waiting process starts immediately.

Using `ExSleeplock.execute/2` is the easiest way to use this library but you can
manage your own lock and timing of execution of a block of code using
`ExSleeplock.acquire/1` (blocking) or `ExSleeplock.attempt/1` (non-blocking). If you
are using those Sleepwalk this way then you are responsible for ensuring
`ExSleeplock.release/1` is called. Until `ExSleeplock.release/1` is called a slot is
being used and a new process may not be able to move forward.

When a lock is created the sleep lock code creates a monitor on the process
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

If you start an iex session for this project you should be able to paste this
code in and run it. It runs 2 tasks at a time with a second in between each
group of 2.

```
defmodule TestSleepwalk do
  def process(name, wait_time_in_ms, idx) do
    ExSleeplock.execute(name, fn ->
      IO.puts("Locked #{idx} at: #{:os.system_time(:milli_seconds)}.")
      Process.sleep(wait_time_in_ms)
      IO.puts("Releasing #{idx} at: #{:os.system_time(:milli_seconds)}.")
      idx
    end)
  end
end

:ok = ExSleeplock.new(:test_sleepwalk, 2)
tasks = Enum.map(1..6, fn idx -> Task.async(fn -> TestSleepwalk.process(:test_sleepwalk, 1_000, idx) end) end) |> Task.await_many(10_000)
```

## Details On What Is Actually Going On

If we had output happening on our acquire & release code, what would it look like?
Let's assume we're running the same code described above in "Trying It Out in iex".
That is, there are 2 slots but 4 processes wanting to run. This is what we'd see
(with some comments added as explanation):

```
# first task calls acquire and it works!
calling acquire: {#PID<0.250.0>, #Reference<0.316635732.565706754.204882>}
acquire. lock granted: {#PID<0.250.0>, #Reference<0.316635732.565706754.204882>}

# second task calls acquire and it works!
calling acquire: {#PID<0.251.0>, #Reference<0.316635732.565706761.204521>}
acquire. lock granted: {#PID<0.251.0>, #Reference<0.316635732.565706761.204521>}

# third task calls acquire and the lock is denied. this process is added to our queue
calling acquire: {#PID<0.252.0>, #Reference<0.316635732.565706754.204883>}
acquire. lock denied. adding to queue: {#PID<0.252.0>, #Reference<0.316635732.565706754.204883>}

# fourth task calls acquire and the lock is denied. this process is added to our queue
calling acquire: {#PID<0.253.0>, #Reference<0.316635732.565706754.204884>}
acquire. lock denied. adding to queue: {#PID<0.253.0>, #Reference<0.316635732.565706754.204884>}

# when one of the first two running processes releases its lock the
# function `next_caller/1` is called. This examines the queue to see what
# is the next function to run. There's two waiting and the first will be
# granted the lock that was just released and removed from the `waiting` queue.
calling next_caller: %Sleeplock.Slot{
  current: %{#PID<0.251.0> => #Reference<0.316635732.565706754.204892>},
  slots: 2,
  waiting: {[{#PID<0.253.0>, #Reference<0.316635732.565706754.204884>}],
   [{#PID<0.252.0>, #Reference<0.316635732.565706754.204883>}]}
}
next_caller, returning :ok for process in queue: {#PID<0.252.0>, #Reference<0.316635732.565706754.204883>}

# The second process in first group releases its lock. `next_caller/1` is
# called again and there's still one more process waiting to run so it
# gets the lock and runs
calling next_caller: %Sleeplock.Slot{
  current: %{#PID<0.252.0> => #Reference<0.316635732.565706761.204552>},
  slots: 2,
  waiting: {[], [{#PID<0.253.0>, #Reference<0.316635732.565706754.204884>}]}
}
next_caller, returning :ok for process in queue: {#PID<0.253.0>, #Reference<0.316635732.565706754.204884>}

# when release is called by the last 2 processes, the `waiting` element in our
# GenServer state is empty. Nothing left to do.
calling next_caller: %Sleeplock.Slot{
  current: %{#PID<0.252.0> => #Reference<0.316635732.565706761.204552>},
  slots: 2,
  waiting: {[], []}
}
calling next_caller: %Sleeplock.Slot{current: %{}, slots: 2, waiting: {[], []}}
```

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
