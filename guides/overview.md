# Overview

Absinthe provides the [absinthe_phoenix](https://hex.pm/packages/absinthe_phoenix) library, which
allows a Phoenix application to register a new socket to receive GraphQL messages over a Phoenix
channel. The downside of this is that clients of this must connect to the websocket with a
Phoenix-specific client library.

The [GraphQL over WebSocket
Protocol](https://github.com/enisdenjo/graphql-ws/blob/master/PROTOCOL.md) is an attempt to define a
generic transport protocol with few or no dependencies that is simple to implement.

This library implements a socket that can be `use`'d by a module and added to a Phoenix endpoint.
