defmodule ExSleeplock.TelemetryTestHelp do
  @moduledoc """
  Helper module for testing telemetry events
  """

  @doc """
  Attach to many events
  """
  @spec attach_to_many_events(atom(), [[atom(), ...]]) :: any()
  def attach_to_many_events(test, event_names) do
    pid = self()

    :telemetry.attach_many(
      "#{test}",
      event_names,
      &ExSleeplock.TelemetryTestHelp.event_handler/4,
      pid
    )
  end

  @doc """
  Remove our telemetry hook
  """
  @spec detach_from_event(atom()) :: any()
  def detach_from_event(test) do
    :telemetry.detach("#{test}")
  end

  def event_handler(name, measurements, metadata, pid) do
    send(pid, {:telemetry_event, name, measurements, metadata})
  end
end
