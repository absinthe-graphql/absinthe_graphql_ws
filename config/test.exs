import Config

config :phoenix, :json_library, Jason
config :absinthe_graphql_ws, Test.Site.Endpoint, pubsub_server: Test.Site.EndpointPubSub
config :logger, level: :error
