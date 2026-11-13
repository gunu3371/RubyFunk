// `@rubyfunk/host/effect` — the Effect-native surface (RFC §7): the `RubyFunkHost` service
// tag + live layer, the wire schemas, typed errors, and Stream accessors. The package root
// (`@rubyfunk/host`) is the Promise facade; this entry is for plugins and Effect programs.
//
//   import { Effect, Stream } from "effect";
//   import { RubyFunkHost, RubyFunkHostLive, events } from "@rubyfunk/host/effect";
//
//   const program = Effect.gen(function* () {
//     yield* events().pipe(
//       Stream.filter((e) => e.kind === "stream.started"),
//       Stream.runForEach((e) => Effect.log(`stream started: ${e.stream.mode}`)),
//     );
//   });
//   Effect.runPromise(program.pipe(Effect.provide(RubyFunkHostLive())));
import { Effect, Layer, type Schema as S, Stream } from "effect";
import {
	EventStreamError,
	makeService,
	RubyFunkHost,
	type RequestError,
	TransportError,
	type VersionSkew,
} from "./client.js";
import { type ConnectOptions, resolveConfig } from "./config.js";
import type { EventStreamOptions, SseFrame } from "./sse.js";
import type { HostEvent } from "./wire.js";

// Everything platform-neutral is `/core`; this entry is that plus the Node half.
export * from "./core.js";
export { type ConnectOptions, configDir, resolveConfig } from "./config.js";

/**
 * The live layer: resolves URL/token/CA (env → host files) and provides [`RubyFunkHost`].
 * Node only, because the resolution is; a browser builds a connection and uses `layerFrom`.
 */
export const layer = (
	options?: ConnectOptions,
): Layer.Layer<RubyFunkHost, TransportError> =>
	Layer.effect(
		RubyFunkHost,
		Effect.tryPromise({
			try: () => resolveConfig(options),
			catch: (cause) => new TransportError({ cause }),
		}).pipe(Effect.map(makeService)),
	);

/** RFC-spelled alias of [`layer`]. */
export const RubyFunkHostLive = layer;

/** The decoded lifecycle-event stream of the ambient [`RubyFunkHost`]. */
export const events = (
	opts?: EventStreamOptions,
): Stream.Stream<HostEvent, EventStreamError, RubyFunkHost> =>
	Stream.unwrap(Effect.map(RubyFunkHost, (s) => s.events(opts)));

/** Every SSE frame verbatim (the `dropped` marker + unknown kinds included). */
export const eventsRaw = (
	opts?: EventStreamOptions,
): Stream.Stream<SseFrame, EventStreamError, RubyFunkHost> =>
	Stream.unwrap(Effect.map(RubyFunkHost, (s) => s.eventsRaw(opts)));

/** One management-API request under `/api/v1` on the ambient service. */
export const request = (
	method: string,
	path: string,
	body?: unknown,
): Effect.Effect<unknown, RequestError, RubyFunkHost> =>
	Effect.flatMap(RubyFunkHost, (s) => s.request(method, path, body));

/** GET + schema-validate on the ambient service (schemas from [`api`]). */
export const get = <A, I>(
	path: string,
	schema: S.Codec<A, I>,
): Effect.Effect<A, RequestError | VersionSkew, RubyFunkHost> =>
	Effect.flatMap(RubyFunkHost, (s) => s.get(path, schema));
