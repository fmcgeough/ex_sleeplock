defmodule ExSleeplock.ApplicationTest do
  @moduledoc false

  use ExUnit.Case

  describe "startup_locks/0" do
    test "no locks configured returns empty list" do
      Application.put_env(:ex_sleeplock, :locks, [])
      assert [] == ExSleeplock.Application.startup_locks()
      Application.delete_env(:ex_sleeplock, :locks)
    end

    test "valid lock; returns child spec" do
      lock_info = %{name: :ex_sleeplock_test, num_slots: 1}
      Application.put_env(:ex_sleeplock, :locks, [lock_info])
      assert [ExSleeplock.StartupLocks] == ExSleeplock.Application.startup_locks()
      Application.delete_env(:ex_sleeplock, :locks)
    end
  end
end
