defmodule ExSleeplock.Slot do
  @moduledoc false

  defstruct slots: 0, current: %{}, waiting: nil

  @typedoc """
  Each lock stored this struct in its state
  """
  @type t() :: %{
          slots: pos_integer(),
          current: map(),
          waiting: :queue.queue()
        }

  @doc """
  Create a new slot record with a waiting queue
  """
  def new(slots) when is_integer(slots) and slots > 0 do
    %__MODULE__{slots: slots, current: %{}, waiting: :queue.new()}
  end
end
