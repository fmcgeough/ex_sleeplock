defmodule ExSleeplock.ApplicationTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias ExSleeplock.LockSupervisor

  describe "configured_locks/0" do
    test "no locks configured returns empty list" do
      Application.put_env(:ex_sleeplock, :locks, [])
      assert [] == ExSleeplock.Application.configured_locks()
    end

    test "valid lock; returns child spec" do
      lock_info = %{name: :ex_sleeplock_test, num_slots: 1}
      Application.put_env(:ex_sleeplock, :locks, [lock_info])
      expected_spec = LockSupervisor.lock_child_spec(lock_info)
      assert [expected_spec] == ExSleeplock.Application.configured_locks()
    end

    test "valid locks; all are returned" do
      locks = Enum.map([:test1, :test2, :test3], fn name ->
        %{name: name, num_slots: 1}
      end)

      Application.put_env(:ex_sleeplock, :locks, locks)
      specs = Enum.map(locks, &LockSupervisor.lock_child_spec/1)
      assert specs == ExSleeplock.Application.configured_locks()
    end

    test "invalid locks are ignored" do
      locks = Enum.map([:test1, :test2, :test3], fn name ->
        %{name: name, num_slots: 1}
      end)

      Application.put_env(:ex_sleeplock, :locks, [%{test123: :invalid}] ++ locks ++ [%{test: :invalid}])
      specs = Enum.map(locks, &LockSupervisor.lock_child_spec/1)
      assert specs == ExSleeplock.Application.configured_locks()
    end
  end
end
