defmodule ExSleeplock.StartupLocksTest do
  @moduledoc false
  use ExUnit.Case, async: false

  import Mox
  import ExSleeplock.TelemetryTestHelp

  alias ExSleeplock.EventGenerator.LockTelemetry
  alias ExSleeplock.EventGeneratorMock
  alias ExSleeplock.StartupLocks

  @lock_create_event [:ex_sleeplock, :lock_created]

  # Mox should be global since we're working with a GenServer (another process)
  setup :set_mox_global
  setup :verify_on_exit!

  describe "configured_locks/0" do
    test "no locks configured returns empty list" do
      Application.put_env(:ex_sleeplock, :locks, [])
      assert [] == StartupLocks.configured_locks()
      Application.delete_env(:ex_sleeplock, :locks)
    end

    test "valid lock; returns child spec" do
      lock_info = %{name: :ex_sleeplock_test, num_slots: 1}
      Application.put_env(:ex_sleeplock, :locks, [lock_info])
      assert [lock_info] == StartupLocks.configured_locks()
      Application.delete_env(:ex_sleeplock, :locks)
    end

    test "valid locks; all are returned" do
      locks =
        Enum.map([:test1, :test2, :test3], fn name ->
          %{name: name, num_slots: 1}
        end)

      Application.put_env(:ex_sleeplock, :locks, locks)
      assert locks == StartupLocks.configured_locks()
      Application.delete_env(:ex_sleeplock, :locks)
    end

    test "invalid locks are ignored" do
      locks =
        Enum.map([:test1, :test2, :test3], fn name ->
          %{name: name, num_slots: 1}
        end)

      Application.put_env(
        :ex_sleeplock,
        :locks,
        [%{test123: :invalid}] ++ locks ++ [%{test: :invalid}]
      )

      assert locks == StartupLocks.configured_locks()
      Application.delete_env(:ex_sleeplock, :locks)
    end

    test "env setting is not a list is ignored" do
      Application.put_env(:ex_sleeplock, :locks, 47)
      assert [] == StartupLocks.configured_locks()
      Application.delete_env(:ex_sleeplock, :locks)
    end
  end

  describe "create locks on start" do
    setup do
      stub_with(EventGeneratorMock, LockTelemetry)
      :ok
    end

    test "locks in application env are created when StartupLocks starts", %{test: lock_name} do
      attach_to_many_events(lock_name, LockTelemetry.events())

      locks = Enum.map([:test1, :test2], fn name -> %{name: name, num_slots: 1} end)

      Application.put_env(:ex_sleeplock, :locks, locks)

      opts = [name: lock_name]
      start_supervised!({StartupLocks, opts})

      for lock_info <- locks do
        assert_receive {:telemetry_event, @lock_create_event, %{value: 1}, ^lock_info}, 500
      end

      Application.delete_env(:ex_sleeplock, :locks)
    end
  end
end
