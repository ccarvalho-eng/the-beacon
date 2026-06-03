defmodule TheBeacon.Event do
  @moduledoc """
  Normalized monitor event emitted by Beacon monitors.
  """

  @enforce_keys [:id, :source, :title, :url]
  defstruct [:id, :source, :title, :url, details: nil]

  @type t :: %__MODULE__{
          id: String.t(),
          source: String.t(),
          title: String.t(),
          url: String.t(),
          details: String.t() | nil
        }
end
