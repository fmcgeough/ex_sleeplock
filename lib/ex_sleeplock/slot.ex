defmodule ExSleeplock.Slot do
  @moduledoc false

  defstruct name: nil, num_slots: 0, current: %{}, waiting: nil

  alias ExSleeplock.EventGenerator

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
  @spec lock_info(t()) :: ExSleeplock.lock_info()
  def lock_info(slot) do
    %{name: slot.name, num_slots: slot.num_slots}
  end

  @doc """
  Return the lock state - number of processes running and waiting
  """
  @spec lock_state(t()) :: ExSleeplock.lock_state()
  def lock_state(slot) do
    %{running: Enum.count(slot.current), waiting: :queue.len(slot.waiting)}
  end

  @doc """
  Generate metric event
  """
  @spec generate_event(atom(), t()) :: any
  def generate_event(event_type, slot) do
    lock_state = lock_state(slot)
    lock_info = lock_info(slot)

    case event_type do
      :lock_created -> EventGenerator.lock_created(lock_info)
      :lock_acquired -> EventGenerator.lock_acquired(lock_info, lock_state)
      :lock_released -> EventGenerator.lock_released(lock_info, lock_state)
      :lock_waiting -> EventGenerator.lock_waiting(lock_info, lock_state)
    end
  end
end
