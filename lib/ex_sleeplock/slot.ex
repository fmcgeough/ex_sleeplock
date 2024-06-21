defmodule ExSleeplock.Slot do
  @moduledoc false

  defstruct name: nil, num_slots: 0, current: %{}, waiting: nil

  @typedoc """
  Each lock stored this struct in its state
  """
  @type t() :: %{
          name: atom(),
          num_slots: pos_integer(),
          current: map(),
          waiting: :queue.queue()
        }

  @doc """
  Create a new slot record with a waiting queue
  """
  def new(name, slots) when is_atom(name) and is_integer(slots) and slots > 0 do
    %__MODULE__{name: name, num_slots: slots, current: %{}, waiting: :queue.new()}
  end

  @doc """
  Return the lock_info - name and number of slots
  """
  def lock_info(slot) do
    %{name: slot.name, num_slots: slot.num_slots}
  end
end
