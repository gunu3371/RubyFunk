# @rubyfunk/host

TypeScript client for the [RubyFunk](https://git.unom.io/unom/punktfunk) host: every
management-API endpoint typed, plus the host's event stream with reconnect and resume. Built on
[Effect](https://effect.website); you don't need to know Effect to use it.

## Install

The package is on the unom npm registry. Point the `@rubyfunk` scope at it once, in `.npmrc`:

```ini
@rubyfunk:registry=https://git.unom.io/api/packages/unom/npm/
```

```sh
bun add @rubyfunk/host effect     # or: npm i @rubyfunk/host effect
```

`effect` is a peer dependency, so your code and the SDK share one copy.

## Usage

On the host box `connect()` needs no configuration: it reads the URL, token and certificate the
host writes to its config directory.

```ts
import { connect } from "@rubyfunk/host";

const pf = await connect();
const clients = await pf.api.listPairedClients();
console.log(`${clients.length} paired clients`);

pf.events.on("stream.started", (e) => {
  console.log(`${e.stream.client} started ${e.stream.mode}`);
});
```

`@rubyfunk/host/effect` exposes the same client as Effect services and streams, and
`@rubyfunk/host/core` is the Node-free build for a browser.

## Docs

- [Management API](https://docs.punktfunk.unom.io/docs/developers/management-api): credentials,
  how `connect()` resolves them, the entry points, and the OpenAPI reference.
- [Writing plugins](https://docs.punktfunk.unom.io/docs/developers/writing-plugins): run your code
  under the host's plugin runner.
- [Events & hooks](https://docs.punktfunk.unom.io/docs/automation): every event kind and its fields.
- [`examples/`](./examples): runnable scripts, from tailing events to USB passthrough.

## Development

```sh
bun install
bun run gen        # regenerate src/gen/rubyfunk.ts from ../api/openapi.json
bun run typecheck
bun test
```

Tag `sdk-vX.Y.Z` (matching `package.json`) to publish.
