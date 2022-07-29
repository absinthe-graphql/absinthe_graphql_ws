# Changelog

## Unpublished

- Update development dependencies
- Update Elixir, Erlang versions for development
- Use internal module for UUID generation, based on `ecto`'s implementation

## 0.3.5

- Update `uuid` library -> `elixir_uuid`
- Fix `c:Absinthe.GraphqlWS.Socket.handle_init/2` docs
- Add examples to README

## 0.3.4

- Add `Absinthe.GraphqlWS.Client`

## 0.3.3

- Documentation fix.

## 0.3.2

- Bug fix: transient task started in the socket uses a name that will not conflict with Task.

## 0.3.1

- Allow configuration of alternate JSON encoder/decoder
  [pull/3](https://github.com/geometerio/absinthe_graphql_ws/pull/3).
- `Jason` is an optional dependency, so must be declared explicitly in the deps of a parent
  application.

## 0.2.2

- Fix error payloads to handle error array from Absinthe [pull/2](https://github.com/geometerio/absinthe_graphql_ws/pull/2)

## 0.2.1

- Logger statements use macros, so that inspect calls only execute when the log level is set to print
  the statement.
- Removes redundant `:queue_exit` message, since Cowboy already closes WebSocket processes when
  `{:close, code, reason}` is sent to a client.

## 0.2.0

- Adds `Ping` handler.
- Adds `c:Absinthe.GraphqlWS.Socket.handle_init/2` for custom handling of `ConnectionInit`.
- Close socket with `44xx` status code on abnormal client request
  - `4429` - Client sends a duplicate `ConnectionInit` message.
  - `4400` - Client sends a `Subscribe` message before `ConnectionInit`.
  - `4400` - Client sends an unexpected message.

## 0.1.1

- Fix incorrect `@spec` on `c:Absinthe.GraphqlWS.Socket.handle_message/2`.

## 0.1.0

- Initial release.
