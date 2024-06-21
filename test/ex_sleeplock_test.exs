defmodule ExSleeplockTest do
  @moduledoc false

  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Mox
  import ExSleeplock.TelemetryTestHelp

  alias ExSleeplock.EventGenerator.LockTelemetry

  @lock_create_event [:ex_sleeplock, :lock_created]
  @lock_acquired_event [:ex_sleeplock, :lock_acquired]
  @lock_released_event [:ex_sleeplock, :lock_released]

  # Mox should be global since we're working with a GenServer (another process)
  setup :set_mox_global
  setup :verify_on_exit!

  describe "new/2" do
    setup do
      stub_with(ExSleeplock.EventGeneratorMock, ExSleeplock.EventGenerator.NoOp)
      :ok
    end

    test "invalid parameters are rejected" do
      assert {:error, :invalid, ExSleeplock.help()} == ExSleeplock.new(:ExSleeplock_tester, "ABC")
      assert {:error, :invalid, ExSleeplock.help()} == ExSleeplock.new(%{name: "myname"}, 5)
      assert {:error, :invalid, ExSleeplock.help()} == ExSleeplock.new(:ExSleeplock_tester, 0)
    end

    test "creating a ExSleeplock using Module name (which is just an atom) works" do
      assert {:ok, _pid} = ExSleeplock.new(ExSleeplockTest, 1)
      ExSleeplock.Lock.stop_lock_process(ExSleeplockTest)
    end

    test "creating a ExSleeplock using atom works" do
      assert {:ok, _pid} = ExSleeplock.new(:ex_sleeplock_test, _num_slots = 1)
      ExSleeplock.Lock.stop_lock_process(:ex_sleeplock_test)
    end

    test "attempting to create the same ExSleeplock twice fails", %{test: lock_name} do
      assert {:ok, pid} = ExSleeplock.new(lock_name, _num_slots = 1)

      logs =
        capture_log(fn ->
          assert {:error, {:already_started, pid}} == ExSleeplock.new(lock_name, _num_slots = 1)
        end)

      assert logs =~ "[error]"
      assert logs =~ "Unable to start lock"
      ExSleeplock.Lock.stop_lock_process(lock_name)
    end
  end

  describe "acquire/1" do
    setup do
      stub_with(ExSleeplock.EventGeneratorMock, ExSleeplock.EventGenerator.NoOp)
      :ok
    end

    test "trying to use non-existent is error" do
      assert ExSleeplock.acquire(:foo) == {:error, :sleeplock_not_found}
    end

    test "acquire works when lock exists", %{test: lock_name} do
      assert {:ok, _pid} = ExSleeplock.new(lock_name, 2)
      assert :ok == ExSleeplock.acquire(lock_name)
      ExSleeplock.Lock.stop_lock_process(lock_name)
    end
  end

  describe "release/1" do
    setup do
      stub_with(ExSleeplock.EventGeneratorMock, ExSleeplock.EventGenerator.NoOp)
      :ok
    end

    test "trying to use non-existent is error" do
      assert ExSleeplock.release(:foo) == {:error, :sleeplock_not_found}
    end

    test "release when not locked returns :ok", %{test: lock_name} do
      assert {:ok, _pid} = ExSleeplock.new(lock_name, _num_slots = 2)
      assert ExSleeplock.release(lock_name) == :ok
      ExSleeplock.Lock.stop_lock_process(lock_name)
    end

    test "release when locked returns :ok", %{test: lock_name} do
      assert {:ok, _pid} = ExSleeplock.new(lock_name, _num_slots = 2)
      :ok = ExSleeplock.acquire(lock_name)
      assert ExSleeplock.release(lock_name) == :ok
      ExSleeplock.Lock.stop_lock_process(lock_name)
    end
  end

  describe "execute/2" do
    setup do
      stub_with(ExSleeplock.EventGeneratorMock, ExSleeplock.EventGenerator.NoOp)
      :ok
    end

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
    test "lock can restrict parallel processing", %{test: lock_name} do
      # set up our ExSleeplock to allow 2 processes to run in
      # parallel.
      num_slots = 2
      lock_info = %{name: lock_name, num_slots: num_slots}
      expect(ExSleeplock.EventGeneratorMock, :lock_created, 1, fn ^lock_info -> :ok end)
      assert {:ok, _pid} = ExSleeplock.new(lock_name, num_slots)

      # Have each process execute for a few milliseconds
      process_time = 250
      num_processes = 4

      # When a lock is acquired the callback indicates how many locks are in use
      # (how many processes are running with this lock). This should always be less
      # than or equal to the number of slots we have available.
      ExSleeplock.EventGeneratorMock
      |> expect(:lock_acquired, num_processes, fn ^lock_info, lock_state ->
        assert lock_state.running <= num_slots
      end)
      |> expect(:lock_released, num_processes, fn ^lock_info, _lock_state ->
        :ok
      end)

      # Attempt to start 4 processes. The first two should get
      # a lock immediately since there are 2 slots for the lock
      # available. The next two should have to wait until one of
      # the first two finishes.
      tasks =
        Enum.map(1..num_processes, fn idx ->
          Task.async(fn -> Consumer.process(lock_name, process_time, idx) end)
        end)

      # Wait for all the tasks to finish
      Task.await_many(tasks, process_time * 3)

      ExSleeplock.Lock.stop_lock_process(lock_name)
    end
  end

  describe "telemetry generation" do
    setup do
      stub_with(ExSleeplock.EventGeneratorMock, ExSleeplock.EventGenerator.LockTelemetry)
      :ok
    end

    test "expected telemetry events are generated", %{test: lock_name} do
      attach_to_many_events(lock_name, LockTelemetry.events())

      assert {:ok, _pid} = ExSleeplock.new(lock_name, 1)

      # Acquire and release the lock
      ExSleeplock.execute(lock_name, fn -> :ok end)

      lock_info = %{name: lock_name, num_slots: 1}
      assert_receive {:telemetry_event, @lock_create_event, %{value: 1}, ^lock_info}, 500
      assert_receive {:telemetry_event, @lock_acquired_event, %{running: 1, waiting: 0}, ^lock_info}, 500
      assert_receive {:telemetry_event, @lock_released_event, %{running: 0, waiting: 0}, ^lock_info}, 500

      ExSleeplock.Lock.stop_lock_process(lock_name)
    end
  end
end
