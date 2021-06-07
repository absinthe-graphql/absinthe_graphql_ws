{:ok, _} = Application.ensure_all_started(:gun)
Test.Site.Application.start(%{}, %{})
Test.Site.TestPubSub.start_link()

ExUnit.start()
