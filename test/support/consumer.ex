defmodule Consumer do
  @moduledoc false

  def process(sleeplock_name, ms_to_work, idx) do
    ExSleeplock.execute(sleeplock_name, fn ->
      start_time = DateTime.utc_now() |> DateTime.to_unix(:millisecond)
      Process.sleep(ms_to_work)
      end_time = DateTime.utc_now() |> DateTime.to_unix(:millisecond)
      %{start: start_time, end: end_time, idx: idx}
    end)
  end
end
