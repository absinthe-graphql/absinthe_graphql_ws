defmodule Test.Retry do
  @moduledoc false

  def retry(fun) when is_function(fun),
    do: retry_for(5000, fun)

  def retry_for(timeout, fun) when is_function(fun) and is_number(timeout) do
    DateTime.utc_now()
    |> DateTime.add(timeout, :millisecond)
    |> retry_until(fun)
  end

  def retry_until(%DateTime{} = time, fun) when is_function(fun) do
    fun.()
  rescue
    e ->
      if DateTime.compare(time, DateTime.utc_now()) == :gt do
        :timer.sleep(100)
        retry_until(time, fun)
      else
        reraise e, __STACKTRACE__
      end
  end
end
