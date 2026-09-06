# CLAUDE.md

Guidance for working in this repository.

## What this is

`accordkit` is a Dart library — an Accord protocol client (REST + gateway
WebSocket + models). It is a faithful port of the GDScript `accordkit` addon
that ships with Daccord. The Dart and GDScript implementations should stay
behaviourally aligned: same endpoints, same wire payloads, same event names,
same parsing quirks.

When in doubt about intended behaviour, the reference is the GDScript source at
`daccord/addons/accordkit/` in the main Daccord repo.

## Layout

```
lib/
  accordkit.dart                 # barrel: exports the public API
  src/
    core/
      accord_config.dart         # URLs + protocol constants
      accord_client.dart         # top-level façade; owns rest + gateway + APIs
    rest/
      accord_rest.dart           # HTTP client: requests, envelope parsing, 429 retry
      accord_error.dart          # AccordError
      rest_result.dart           # RestResult (ok/data/error)
      endpoint_base.dart         # base class for endpoint groups
      multipart_form.dart        # multipart/form-data builder
      endpoints/*.dart           # one class per endpoint group
    gateway/
      gateway_opcodes.dart       # opcode constants
      gateway_intents.dart       # intent constants + groupings
      gateway_connection.dart    # GatewayConnection abstraction + WS impl
      gateway_events.dart        # DisconnectInfo / ReconnectInfo / RawGatewayEvent
      gateway_socket.dart        # handshake, heartbeat, reconnect, dispatch
    models/*.dart                # data models (fromJson / toJson)
    utils/
      json_utils.dart            # lenient coercion helpers (asString/asInt/...)
      cdn.dart                   # CDN URL builders
test/
  support/                       # test helpers (mock REST, fake gateway connection)
  *_test.dart
example/
```

## Conventions

- **Naming.** GDScript `snake_case` members become Dart `camelCase`; classes
  keep their `Accord*` names. JSON keys on the wire stay `snake_case` — only the
  Dart-side field names are camelCased.
- **Lenient parsing.** Server fields can arrive as ints or strings (snowflakes
  especially). Always parse through the helpers in `utils/json_utils.dart`
  (`asString`, `asStringOrNull`, `asInt`, `asDouble`, `asBool`, `asMap`,
  `asList`) rather than casting directly.
- **`toJson` omits nulls.** Optional fields are only included when non-null,
  matching the GDScript `to_dict()` behaviour. Round-trip tests rely on this.
- **REST results.** Endpoint methods return `RestResult`. Use
  `result.deserialize(Model.fromJson)` for single objects and
  `result.deserializeArray(Model.fromJson)` for lists. Don't throw on HTTP
  errors — surface them via `RestResult.error`.
- **Gateway events.** Each event is a broadcast `Stream` getter named
  `on<Event>`. Typed events carry models; structural events carry
  `Map<String, dynamic>`. Every event is also emitted on `onRawEvent`.

## Testability (important)

The library must be unit-testable without real network access:

- `AccordRest` takes an injectable `http.Client` and a `sleep` callback (so
  rate-limit retries don't actually wait). Tests use
  `package:http/testing.dart`'s `MockClient`.
- `GatewaySocket` takes a `GatewayConnectionFactory`, a `sleep` callback, and a
  `random` callback. Tests inject `FakeGatewayConnection`
  (`test/support/fake_gateway_connection.dart`) to drive frames and simulate
  closes deterministically.

When adding features, preserve these seams. Don't call `DateTime.now()`,
`Random()`, real timers, or real sockets directly in logic that needs testing —
thread them through constructor parameters.

## Commands

```bash
dart pub get        # resolve dependencies
dart analyze        # must be clean (lints in analysis_options.yaml)
dart test           # run the suite
dart test test/gateway_test.dart   # a single file
```

CI expectations: `dart analyze` reports no issues and `dart test` is green.

## When adding an endpoint

1. Add the method to the relevant `src/rest/endpoints/*_api.dart` class
   (create a new class + wire it into `AccordClient` and the barrel if it's a
   new group).
2. Match the GDScript path, HTTP method, body shape, and deserialization.
3. Add a test in `test/endpoints_test.dart` asserting method, path, body, and
   the deserialized type using `mockRest`.

## When adding a gateway event

1. Add a controller + `on<Event>` getter in `gateway_socket.dart`.
2. Add the `case` in `_dispatchEvent` using the exact server event-type string.
3. Forward the getter on `AccordClient`.
4. Add a dispatch test in `test/gateway_test.dart`.
