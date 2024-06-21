defmodule ExSleeplock.Application do
  @moduledoc false

  use Application

  alias ExSleeplock.LockSupervisor

  def start(_type, _args) do
    children = [LockSupervisor] ++ configured_locks()

    Supervisor.start_link(children,
      strategy: :one_for_one,
      name: ExSleeplock.Supervisor
    )
  end

  def configured_locks do
    :ex_sleeplock
    |> Application.get_env(:locks, [])
    |> Enum.filter(&LockSupervisor.valid_lock?/1)
    |> Enum.map(&LockSupervisor.lock_child_spec/1)
  end
end
