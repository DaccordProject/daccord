# CLAUDE.md

`accordkit`: Dart Accord protocol client (REST + gateway WebSocket + models),
originally ported from the GDScript addon (on the `legacy-godot` branch at
`addons/accordkit/`). Keep endpoints, wire payloads, and event names aligned
with the server.

## Conventions

- Dart fields are camelCase; JSON wire keys stay snake_case.
- Parse server fields via `lib/src/utils/json_utils.dart` helpers (`asString`,
  `asInt`, `asMap`, …) — snowflakes may arrive as int or string. Never cast directly.
- `toJson` omits nulls (round-trip tests rely on it).
- Endpoints return `RestResult` (use `deserialize` / `deserializeArray`); never
  throw on HTTP errors.
- Gateway events are broadcast `Stream` getters `on<Event>`, also emitted on `onRawEvent`.

## Testability

No real network, clock, randomness, or timers in logic. `AccordRest` takes an
injectable `http.Client` and `sleep`; `GatewaySocket` takes a connection
factory, `sleep`, and `random`. Tests use `MockClient` and
`test/support/fake_gateway_connection.dart`. Preserve these seams.

## Adding things

- **Endpoint:** method in `lib/src/rest/endpoints/*_api.dart` (new group → wire
  into `AccordClient` + barrel), test in `test/endpoints_test.dart` via `mockRest`.
- **Gateway event:** controller + getter in `gateway_socket.dart`, `case` in
  `_dispatchEvent` with the exact server event string, forward on
  `AccordClient`, dispatch test in `test/gateway_test.dart`.

## Commands

```bash
dart analyze   # must be clean
dart test
```
