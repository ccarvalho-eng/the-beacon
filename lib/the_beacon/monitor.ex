defmodule TheBeacon.Monitor do
  @moduledoc """
  Behaviour for Beacon monitors.
  """

  @callback check(keyword() | map()) ::
              {:ok, [TheBeacon.Event.t()]} | [TheBeacon.Event.t()] | {:error, term()}
end
