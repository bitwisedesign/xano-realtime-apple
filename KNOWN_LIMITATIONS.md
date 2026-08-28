# Known limitations

Upstream Xano Realtime behavior that this SDK cannot work around. Re-check these when Xano publishes Realtime or auth changes.

## Auth tokens must come from the live datasource

Xano Realtime only attaches a user to the socket when `realtimeAuthToken` is a Xano auth token minted against the **live** datasource. A real `create_auth_token` / login JWT from any other data source is accepted as a WebSocket subprotocol (the handshake succeeds) but the socket stays anonymous.

If the channel has **Anonymous Clients** off, join then fails with:

```text
Anonymous clients cannot join this channel.
```

This is not an SDK transport bug. The official JS path is the same: JWT as `Sec-WebSocket-Protocol` on `wss://{host}/rt/{canonical}`. Datasource selection used for HTTP APIs does not apply to that socket.

**Last verified:** 2026-08-28, against this package's example app.

| Token | Channel Anonymous Clients | Result |
| --- | --- | --- |
| Live datasource JWT | Off | Join succeeds as that user |
| JWT from any other data source | Off | Handshake OK; join rejected as anonymous |
| Non-live JWT plus handshake `X-Data-Source` set to that data source | Off | Same rejection (header ignored) |
| Any / none | On | Join succeeds as anonymous |

`X-Data-Source`, `?x-data-source=`, and JS `setDataSource` target **API / function-stack** database access. They are not documented on the Realtime WebSocket, and sending `X-Data-Source` on the upgrade did not change join identity.

Until Xano documents a way to point Realtime at a non-live datasource, develop authenticated channels with a live-datasource user (or copy/migrate that row into live). Use Anonymous Clients on only to test unauthenticated join.

### Sources

Grouped by how they relate to this limitation.

#### Realtime + non-live / anonymous despite a token

- https://community.weweb.io/t/xano-realtime-realtimeauthtoken-present-in-localstorage-but-websocket-connects-as-anonymous/21300
- https://community.xano.com/ask-the-community/post/triggers-and-realtime-in-non-live-branches-x1GtrKxVXc0CsS0
- https://community.xano.com/ask-the-community/post/xano-realtime-setrealtimeauthtoken-not-working-6PWNZRQjEk7AFVA
- https://community.weweb.io/t/xano-realtime-open-channel-with-auth/20934

#### Auth tokens are datasource-scoped (REST)

- https://community.xano.com/ask-the-community/post/authentication-not-working-with-other-data-sources-U8tf22669CVfT9t
- https://docs.xano.com/the-database/database-basics/data-sources

#### Official Realtime docs have no datasource knob

- https://docs.xano.com/realtime/realtime-in-xano
- https://docs.xano.com/realtime/channel-permissions
- https://docs.xano.com/building-features/realtime#xano-auth--realtime
- https://docs.xano.com/xano-features/metadata-api/instanceapi

#### JS SDK: `dataSource` is HTTP only; socket is URL + JWT protocol

- https://raw.githubusercontent.com/xano-inc/js-sdk/main/src/models/realtime-state.ts
- https://raw.githubusercontent.com/xano-inc/js-sdk/main/src/interfaces/client-config.ts
- https://www.npmjs.com/package/@xano/js-sdk
- https://github.com/xano-inc/js-sdk

#### Adjacent (HTTP datasource headers, not the WebSocket)

- https://docs.weweb.io/integrations/xano.html
- https://docs.weweb.io/plugins/auth-systems/xano-auth.html
