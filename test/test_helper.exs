{:ok, _} = Application.ensure_all_started(:gun)
Test.Site.TestPubSub.start_link()

ExUnit.start()
