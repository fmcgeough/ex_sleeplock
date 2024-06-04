defmodule ExSleeplock.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [ExSleeplock.LockSupervisor]

    Supervisor.start_link(children,
      strategy: :one_for_one,
      name: ExSleeplock.Supervisor
    )
  end
end
