defmodule Consumer do
  @moduledoc false

  def process(sleeplock_name, ms_to_work, idx) do
    ExSleeplock.execute(sleeplock_name, fn -> test(ms_to_work, idx) end)
  end

  def acquire_with_no_release(sleeplock_name, ms_to_work, idx) do
    ExSleeplock.acquire(sleeplock_name)
    test(ms_to_work, idx)
  end

  defp test(ms_to_work, idx) do
    start_time = DateTime.utc_now() |> DateTime.to_unix(:millisecond)
    Process.sleep(ms_to_work)
    end_time = DateTime.utc_now() |> DateTime.to_unix(:millisecond)
    %{start: start_time, end: end_time, idx: idx}
  end
end
