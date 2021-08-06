import Config

config :absinthe_graphql_ws, :json_library, Jason

if config_env() == :test do
  import_config("test.exs")
end
