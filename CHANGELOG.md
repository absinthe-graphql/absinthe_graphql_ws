# Changelog

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