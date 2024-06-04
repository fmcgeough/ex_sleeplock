defmodule ExSleeplock.Slot do
  @moduledoc """
  Define the state used by a sleep lock process
  """
  defstruct slots: 0, current: %{}, waiting: nil

  def new(slots) do
    %__MODULE__{slots: slots, current: %{}, waiting: :queue.new()}
  end
end
