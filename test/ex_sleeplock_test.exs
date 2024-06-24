defmodule ExSleeplockTest do
  @moduledoc false

  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Mox
  import ExSleeplock.TelemetryTestHelp

  alias ExSleeplock.EventGenerator.LockTelemetry
  alias ExSleeplock.LockSupervisor

  @lock_create_event [:ex_sleeplock, :lock_created]
  @lock_acquired_event [:ex_sleeplock, :lock_acquired]
  @lock_released_event [:ex_sleeplock, :lock_released]
  @lock_waiting_event [:ex_sleeplock, :lock_waiting]

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
      LockSupervisor.stop_lock(ExSleeplockTest)
    end

    test "creating a ExSleeplock using atom works" do
      assert {:ok, _pid} = ExSleeplock.new(:ex_sleeplock_test, _num_slots = 1)
      LockSupervisor.stop_lock(:ex_sleeplock_test)
    end

    test "attempting to create the same ExSleeplock twice fails", %{test: lock_name} do
      assert {:ok, pid} = ExSleeplock.new(lock_name, _num_slots = 1)

      logs =
        capture_log(fn ->
          assert {:error, {:already_started, pid}} == ExSleeplock.new(lock_name, _num_slots = 1)
        end)

      assert logs =~ "[error]"
      assert logs =~ "Unable to start lock"
      LockSupervisor.stop_lock(lock_name)
    end

    test "creating multiple locks works" do
      assert {:ok, _pid} = ExSleeplock.new(:ex_sleeplock_test1, 1)
      assert {:ok, _pid} = ExSleeplock.new(:ex_sleeplock_test2, 1)
      LockSupervisor.stop_lock(:ex_sleeplock_test1)
      LockSupervisor.stop_lock(:ex_sleeplock_test2)
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
      LockSupervisor.stop_lock(lock_name)
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
      LockSupervisor.stop_lock(lock_name)
    end

    test "release when locked returns :ok", %{test: lock_name} do
      assert {:ok, _pid} = ExSleeplock.new(lock_name, _num_slots = 2)
      assert :ok = ExSleeplock.acquire(lock_name)
      assert :ok == ExSleeplock.release(lock_name)
      LockSupervisor.stop_lock(lock_name)
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
    setup do
      stub_with(ExSleeplock.EventGeneratorMock, ExSleeplock.EventGenerator.NoOp)
      :ok
    end

    test "trying to use non-existent is error" do
      assert ExSleeplock.attempt(:foo) == {:error, :sleeplock_not_found}
    end

    test "if lock is available returns `:ok`", %{test: test} do
      ExSleeplock.new(test, 1)
      assert :ok == ExSleeplock.attempt(test)
      ExSleeplock.release(test)
      LockSupervisor.stop_lock(test)
    end

    test "if lock is unavailable `{:error, :unavailable}` is returned", %{test: test} do
      assert {:ok, _pid} = ExSleeplock.new(test, 1)
      assert :ok == ExSleeplock.attempt(test)
      assert {:error, :unavailable} == ExSleeplock.attempt(test)
      ExSleeplock.release(test)
      LockSupervisor.stop_lock(test)
    end

    test "multiple locks have independent attempt behaviour" do
      assert {:ok, _pid} = ExSleeplock.new(:test1, 1)
      assert {:ok, _pid} = ExSleeplock.new(:test2, 1)

      assert :ok == ExSleeplock.attempt(:test1)
      assert :ok == ExSleeplock.attempt(:test2)

      ExSleeplock.release(:test1)
      ExSleeplock.release(:test2)

      ExSleeplock.Lock.stop_lock_process(:test1)
      ExSleeplock.Lock.stop_lock_process(:test2)
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
      # Since we are running 4 processes we should never have more than num_slots
      # waiting for the lock.
      ExSleeplock.EventGeneratorMock
      |> expect(:lock_acquired, num_processes, fn ^lock_info, lock_state ->
        assert lock_state.running <= num_slots
      end)
      |> expect(:lock_released, num_processes, fn ^lock_info, _lock_state ->
        :ok
      end)
      |> expect(:lock_waiting, num_slots, fn ^lock_info, _lock_state ->
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

      LockSupervisor.stop_lock(lock_name)
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

      LockSupervisor.stop_lock(lock_name)
    end
  end

  describe "lock state" do
    setup do
      stub_with(ExSleeplock.EventGeneratorMock, ExSleeplock.EventGenerator.NoOp)
      :ok
    end

    test "trying to use non-existent is error" do
      assert ExSleeplock.lock_state(:foo) == {:error, :sleeplock_not_found}
    end

    test "when no locks obtained returns 0 running and 0 waiting", %{test: lock_name} do
      stub_with(ExSleeplock.EventGeneratorMock, ExSleeplock.EventGenerator.NoOp)
      assert {:ok, _pid} = ExSleeplock.new(lock_name, 1)
      assert %{running: 0, waiting: 0} == ExSleeplock.lock_state(lock_name)
      LockSupervisor.stop_lock(lock_name)
    end

    test "when lock is obtained and one is waiting the correct state is returned", %{test: lock_name} do
      stub_with(ExSleeplock.EventGeneratorMock, ExSleeplock.EventGenerator.LockTelemetry)
      attach_to_many_events(lock_name, LockTelemetry.events())
      lock_info = %{name: lock_name, num_slots: 1}

      process_time = 500
      assert {:ok, _pid} = ExSleeplock.new(lock_name, 1)

      assert :ok == ExSleeplock.acquire(lock_name)
      assert_receive {:telemetry_event, @lock_acquired_event, %{running: 1, waiting: 0}, ^lock_info}, 500
      assert %{running: 1, waiting: 0} == ExSleeplock.lock_state(lock_name)

      task = Task.async(fn -> ExSleeplock.execute(lock_name, fn -> Process.sleep(process_time) end) end)
      assert_receive {:telemetry_event, @lock_waiting_event, %{running: 1, waiting: 1}, ^lock_info}, 500

      assert %{running: 1, waiting: 1} == ExSleeplock.lock_state(lock_name)

      # Release the lock
      ExSleeplock.release(lock_name)

      # Wait for the task to complete
      Task.await(task)

      LockSupervisor.stop_lock(lock_name)
    end
  end
end
