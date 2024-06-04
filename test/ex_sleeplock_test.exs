defmodule ExSleeplockTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  doctest ExSleeplock

  describe "new/2" do
    test "invalid parameters are rejected" do
      assert {:error, :invalid, ExSleeplock.help()} == ExSleeplock.new(:ExSleeplock_tester, "ABC")
      assert {:error, :invalid, ExSleeplock.help()} == ExSleeplock.new(%{name: "myname"}, 5)
      assert {:error, :invalid, ExSleeplock.help()} == ExSleeplock.new(:ExSleeplock_tester, 0)
    end

    test "creating a ExSleeplock using Module name (which is just an atom) works" do
      logs =
        capture_log(fn ->
          {:ok, pid} = ExSleeplock.new(ExSleeplockTest, 1)
          assert pid
          Process.exit(pid, :normal)
        end)

      assert logs =~ "Starting lock Elixir.ExSleeplockTest"
    end

    test "creating a ExSleeplock using atom works" do
      {:ok, pid} = start_supervised({ExSleeplock, %{name: :ExSleeplock_tester, num_slots: 1}})
      assert pid
    end

    test "attempting to create the same ExSleeplock twice fails" do
      {:ok, pid} = start_supervised({ExSleeplock, %{name: :ExSleeplock_tester, num_slots: 1}})
      assert pid

      logs =
        capture_log(fn ->
          assert {:error, {:already_started, pid}} == ExSleeplock.new(:ExSleeplock_tester, 1)
        end)

      assert logs =~ "error"
      assert logs =~ "Unable to start lock ExSleeplock_tester"
    end
  end

  describe "acquire/1" do
    test "trying to use non-existent is error" do
      assert ExSleeplock.acquire(:foo) == {:error, :sleeplock_not_found}
    end

    test "acquire works when lock exists" do
      name = :acquire_testing
      start_supervised({ExSleeplock, %{name: name, num_slots: 2}})
      assert :ok == ExSleeplock.acquire(name)
    end
  end

  describe "release/1" do
    test "trying to use non-existent is error" do
      assert ExSleeplock.release(:foo) == {:error, :sleeplock_not_found}
    end

    test "release when not locked returns :ok" do
      name = :release_testing
      start_supervised({ExSleeplock, %{name: name, num_slots: 2}})
      assert ExSleeplock.release(name) == :ok
    end

    test "release when locked returns :ok" do
      name = :release_testing
      start_supervised({ExSleeplock, %{name: name, num_slots: 2}})
      :ok = ExSleeplock.acquire(name)
      assert ExSleeplock.release(name) == :ok
    end
  end

  describe "execute/2" do
    test "trying to use non-existent is error" do
      fun = fn -> "ABC" end
      assert ExSleeplock.execute(:foo, fun) == {:error, :sleeplock_not_found}
    end
  end

  describe "attempt/1" do
    test "trying to use non-existent is error" do
      assert ExSleeplock.attempt(:foo) == {:error, :sleeplock_not_found}
    end
  end

  describe "ensure that we can only execute n processes in parallel" do
    test "running 2 in parallel at a time" do
      # set up our ExSleeplock to allow 2 processes to run in
      # parallel.
      start_supervised({ExSleeplock, %{name: :parallel_test, num_slots: 2}})

      # Have each process execute for 500 ms
      process_time = 500
      max_time_between_first_and_second = process_time + 10

      # Start first group of two processes. These will be able to get
      # a lock immediately since there are 2 slots for the lock
      first_group =
        Enum.map(0..1, fn idx ->
          Task.async(fn -> Consumer.process(:parallel_test, process_time, idx) end)
        end)

      # Start second group of two processes. These will have to wait
      # when started because no slots are available. As soon as one of
      # processes in the first group finishes, one of these will start
      # running.
      second_group =
        Enum.map(2..3, fn idx ->
          Task.async(fn -> Consumer.process(:parallel_test, process_time, idx) end)
        end)

      # Wait for all the tasks to finish
      results = first_group |> Enum.concat(second_group) |> Task.await_many(process_time * 3)

      # Our first two tasks should have started about the same time since
      # there were 2 slots available. In practice these are going to be within
      # 1 ms but give a bit extra
      [start_0, start_1] = results |> Enum.filter(&(&1.idx < 2)) |> Enum.map(& &1.start)
      tasks_start_diff = abs(start_0 - start_1)
      assert tasks_start_diff <= 10

      # Our next two tasks should have started about the same time. In practice
      # these are going to be within 1 ms but give a bit extra
      [start_2, start_3] = results |> Enum.filter(&(&1.idx > 1)) |> Enum.map(& &1.start)
      tasks_start_diff = abs(start_2 - start_3)
      assert tasks_start_diff <= 10

      # our second group should have started at least 500 ms after the first one.
      # We cannot test for the exact time of 500 ms due to variations in test
      # enviroonments, etc. But the test assumes that it'll never be more than
      # a 10ms gap. We're testing that it doesn't take an unexpectedly long time
      # to start the second group after doing the first
      diff_between_first_and_second_group = abs(start_2 - start_0)
      assert diff_between_first_and_second_group >= process_time
      assert diff_between_first_and_second_group <= max_time_between_first_and_second
    end
  end
end
