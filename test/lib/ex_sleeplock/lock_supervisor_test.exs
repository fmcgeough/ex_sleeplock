defmodule ExSleeplock.LockSupervisorTest do
  @moduledoc false
  use ExUnit.Case

  describe "stop_lock/1" do
    test "stop lock that does not exist returns error" do
      assert {:error, :sleeplock_not_found} == ExSleeplock.LockSupervisor.stop_lock(:foo)
    end
  end

  describe "lock_child_spec/1" do
    test "valid lock_info returns child spec" do
      lock_info = %{name: :ex_sleeplock_test, num_slots: 1}

      expected_spec = %{
        id: ExSleeplock,
        start: {ExSleeplock.Lock, :start_link, [lock_info]},
        restart: :permanent,
        type: :worker
      }

      assert expected_spec == ExSleeplock.LockSupervisor.lock_child_spec(lock_info)
    end

    test "invalid lock_info raises ArgumentError" do
      invalid_lock = %{test123: :invalid}
      str = "Invalid lock info: #{inspect(invalid_lock)}"

      assert_raise ArgumentError, str, fn ->
        ExSleeplock.LockSupervisor.lock_child_spec(invalid_lock)
      end
    end
  end
end
