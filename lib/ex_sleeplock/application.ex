defmodule ExSleeplock.Application do
  @moduledoc false

  use Application

  alias ExSleeplock.LockSupervisor
  alias ExSleeplock.StartupLocks

  def start(_type, _args) do
    children = [LockSupervisor] ++ startup_locks()

    Supervisor.start_link(children, strategy: :rest_for_one, name: ExSleeplock.Supervisor)
  end

  def startup_locks do
    StartupLocks.configured_locks()
    |> Enum.empty?()
    |> case do
      true -> []
      false -> [StartupLocks]
    end
  end
end
