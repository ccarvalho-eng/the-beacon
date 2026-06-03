defmodule TheBeacon.NotificationDelivery do
  @moduledoc """
  Behaviour for delivering normalized monitor events.
  """

  @callback deliver([TheBeacon.Event.t()], keyword() | map()) :: :ok | {:error, term()}
end
