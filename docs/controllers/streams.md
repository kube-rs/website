# Streams

This chapter is about watcher streams and their use in controllers:

We will first cover:

- [watcher] / [metadata_watcher] stream entrypoints
- working with watcher streams using [WatchStreamExt]

and then the `unstable-runtime` controller streams interface

- [Controller::for_stream] - analogue for `Controller::new`
- [Controller::watches_stream] - analogue for `Controller::watches`
- [Controller::owns_stream] - analogue for `Controller::owns`

Together these sets of apis enable controller [[optimization]], as well as stream sharing between co-hosted controllers ([WIP#1080](https://github.com/kube-rs/kube/issues/1080))

## Stream Entrypoints

All watcher streams are started by either [watcher] or [metadata_watcher].

### Watcher
A [watcher] is a high level primitive combining `Api::watch` and `Api::list` to provide an infinite watch `Stream` while handling all the error cases.

The watcher `Stream` can be passed through cache writers (via [reflector]), passed on to controllers (or created implicitly by the `Controller`), or even observed directly:

```rust
let api = Api::<Pod>::default_namespaced(client);
watcher(api, watcher::Config::default())
    .applied_objects()
    .default_backoff()
    .try_for_each(|p| async move {
        info!("saw {}", p.name_any());
        Ok(())
    }).await?;
```

The above example will run continuously until the end of the program. Note that as `watcher` produces an async rust stream, it **must be polled** to actually call the underlying api and do the work.

### Metadata Watcher

A [metadata_watcher] is a [watcher] analogue that using the **metadata api** that **only** returns [TypeMeta] (`.api_version` + `.kind`) + [ObjectMeta] (`.metadata`).

This can generally be used as a **drop-in replacement** for [watcher] provided you do not need data in `.spec` or `.status`.

This means less IO, and less memory usage (especially if you are using it with a [reflector]). See the **[[optimization]] chapter** for details.

You can generally **replace** `watcher` with `metadata_watcher` in the examples above as:

```diff
# General change:
-let stream =          watcher(api, cfg).applied_objects();
+let stream = metadata_watcher(api, cfg).applied_objects();

# Same change inside a reflector:
-let stream = reflector(writer,          watcher(api, cfg)).applied_objects();
+let stream = reflector(writer, metadata_watcher(api, cfg)).applied_objects();
```

But note this changes the stream signature slightly; returning a wrapped [PartialObjectMeta].

## Watcher Streams
### Terminology

- **watcher stream** :: a stream that is started by one of the watcher [[#stream-entrypoints]]
- **decoded stream** :: a stream that's been through [EventDecode] via one of `WatchStreamExt::touched_objects`, `WatchStreamExt::applied_objects`
- **event stream** :: a raw [watcher] stream producing [watcher::Event] objects

The significant difference between them is that the **user** and the [Controller] generally wants to interact with an **decoded stream**, but a [reflector] needs an **event stream** to be able to safely replace its contents.

### WatchStreamExt
The [WatchStreamExt] trait is a `Stream` extension trait (ala [StreamExt]) with Kubernetes specific helper methods that can be chained onto a watcher stream;

```rust
watcher(api, watcher::Config::default())
    .default_backoff()
    .modify(|x| { x.managed_fields_mut().clear(); })
    .applied_objects()
    .predicate_filter(predicates::generation)
```

These methods can require one of:

- **event stream** (where the input stream `Item = Result<Event<K>, ...>`
- **decoded stream** (where `Item = Result<K, ...>`, the last ones in the chain)

It is impossible to apply them in an incompatible configuration.

## Stream Mutation
It is possible to modify or filter the input streams before passing them on. This can usually either done to limit data in memory by pruning, or to filter events to a downstream controller so that it either triggers less frequently.

### Predicates
Using [predicates], we can **filter out** events from a stream where the **last value** of a particular property is **unchanged**. This is done internally by storing hashes of the given property(ies), and can be chained onto an **decoded** stream:

```rust
let api: Api<Deployment> = Api::all(client);
let stream = watcher(api, cfg)
    .applied_objects()
    .predicate_filter(predicates::generation);
```

in this case, deployments with the last previously seen `.metadata.generation` hash will be filtered out from the stream.

A generation predicate effectively filters out changes that only affect the `.status` object (for resources that support .generation), and is one useful way to avoding reconcile changes to your own CR re-triggering your reconciler.

We can additionally wrap a [reflector] around the raw watcher stream before doing the filter. This ensures we still have the most up-to-date value received in the cache:

```rust
let stream = reflector(writer, watcher(api, cfg))
    .applied_objects()
    .predicate_filter(predicates::generation);
```

### Event Modification
You can modify raw objects in flight before they are passed on to a reflector or controller. This can help minimise [reflector] memory consumption by [[optimization#pruning-fields]].

```rust
let stream = watcher(pods, cfg).modify(|pod| {
    pod.managed_fields_mut().clear();
    pod.status = None;
});
let (reader, writer) = reflector::store::<Pod>();
let rf = reflector(writer, stream).applied_objects();
```

!!! note "Ordering"

    It is possible to do the modification after the `reflector` call, but this would result in the modification not being persisted in the store and merely passed on in the stream.


## Controller Streams

By **default**, [watcher] streams are **implicitly configured** within the [Controller], but using the controller streams interface setup introduced in [kube 0.81](https://github.com/kube-rs/kube/releases/tag/0.81.0) you can **explicitly setup** all the [watcher] stream for more precise targeting:

```rust
Controller::for_stream(main_stream, reader)
    .owns_stream(owned_custom_stream, cfg)
    .watches_stream(watched_custom_stream, cfg)
```

where the various stream variables would be created from either [watcher], or [metadata_watcher] with some filters applied.

!!! warning "The controller streams interface is unstable"

    Currently plugging streams into [Controller] requires the `kube/unstable-runtime` feature. This interface is planned to be stabilized in a future release.

### Output Stream

To start a controller, you typically invoke `Controller::run`, and this actually produces a stream of object references that are yielded after being passed through the reconciler.

This is not important from a data-perspective (as you will see everything from `reconcile`), but it is the stream that back-propagates through the stream of streams that the `Controller` ultimately manages. The key point:

!!! warning "Polling"

     You must continuously poll the output stream to cause the controller to work.

You can do this by looping through the output stream:

```rust
Controller::new(api, Config::default())
    .run(reconcile, error_policy, context)
    .filter_map(|x| async move { std::result::Result::ok(x) })
    .for_each(|_| futures::future::ready(()))
    .await;
```

### Input Streams
To configure one of the input streams manually you need to:

1. create a watcher stream with backoff
2. decode the stream
3. call the stream-equivalent `Controller` interface

Note that the `Controller` will poll all the passed (or implicitly created) watcher streams as a whole when you poll the output stream from the controller.

#### Main Stream
The controller runtime requires a [reflector] for the main api, so you must also create a [reflector] pair yourself in this case:

```diff
 let cfg = watcher::Config::default();
 let api = Api::<MyCustomResource>::all(client.clone());
+let (reader, writer) = reflector::store();
+let stream = reflector(writer, watcher(api, cfg))
+    .default_backoff()
+    .applied_objects();

-Controller::new(api, cfg)
+Controller::for_stream(stream, reader)
```

leaving additionally the `reader` in your hands should you need it (obviating the non-stream requirement to call to `Controller::store`). The `Controller` will wait for the `Store` (reader) to be populated until starting reconciles.

!!! note "Metadata Watchers on Main Controller Stream"

    Using [metadata_watcher] on the main stream (using `Controller::for_stream`) changes the `reconcile` / `error_policy` type signature from returning objects of form `Arc<K>` to `Arc<PartialObjectMeta<K>>`:

    ```diff
    -async fn reconcile(_: Arc<Deployment>, _: Arc<()>) ...
    +async fn reconcile(_: Arc<PartialObjectMeta<Deployment>>, _: Arc<()>) ...
    -fn error_policy(_: Arc<Deployment>, _: &kube::Error, _: Arc<()>) ...
    +fn error_policy(_: Arc<PartialObjectMeta<Deployment>>, _: &kube::Error, _: Arc<()>) ...
    ```

    This means the object you get in your reconciler is just a partial object with only `.metadata`. You can call `api.get()` inside `reconcile` to get a full object if needed.

#### Owned Stream
As per [[relations]], this requires your owned objects to have owner refrences back to your main object (`cr`):

```diff
 let cfg_owned = watcher::Config::default();
 let cfg_cr = watcher::Config::default();
 let cr: Api<MyCustomResource> = Api::all(client.clone());
 let owned_api: Api<Deployment> = Api::default_namespaced(client);
+let deploys = metadata_watcher(owned_api, cfg_owned).default_backoff().applied_objects();

 Controller::new(cr, cfg_cr)
-    .owns(owned_api, cfg_owned)
+    .owns_stream(deploys)
```

!!! note "Metadata Watcher Default"

    [[#Metadata-Watcher]] is used in [Controller::owns] for its stream, as the reverse mapping (say from `Deployment` to `MyCustomResource`) is always done entirely with metadata properties. As such, it is also the recommended default for [Controller::owns_stream].

#### Watched Stream
As per [[relations]], this requires a custom mapper mapping back to your main object (`cr`):

```diff
 fn mapper(_: DaemonSet) -> Option<ObjectRef<MyCustomResource>> { todo!() }

 let cfg_ds = watcher::Config::default();
 let cfg_cr = watcher::Config::default();
 let cr_api: Api<MyCustomResource> = Api::all(client.clone());
 let ds_api: Api<DaemonSet> = Api::all(client);
+let daemons = watcher(ds_api, cfg_ds).default_backoff().touched_objects();

 Controller::new(cr_api, cfg_cr)
-    .watches(ds_api, cfg_ds, mapper)
+    .watches_stream(daemons, mapper)
```

This often combines cleanly with [[#Metadata-Watcher]] when the `mapper` only relies on metadata properties.



### Multi Stream Example
A more advanced example using:

- main stream through a [watcher] + [reflector] with [predicates]
- owned stream through a [metadata_watcher]

```rust
let cfg_owned = watcher::Config::default();
let cfg_cr = watcher::Config::default();

let api_owned = Api::<PartialObjectMeta<Deployment>>::all(client.clone());
let api_cr = Api::<MyCustomResource>::all(client.clone());

let (reader, writer) = reflector::store();
let cr_stream = reflector(writer, watcher(api_cr, cfg_cr))
    .default_backoff()
    .applied_objects()
    .predicate_filter(predicates::generation);

let owned_stream = metadata_watcher(api_owned, cfg_owned)
    .default_backoff()
    .touched_objects();

Controller::for_stream(cr_stream, reader)
    .owns_stream(owned_stream)
    .run(reconcile, error_policy, Arc::new(()))
    .for_each(|_| std::future::ready(()))
    .await;
```


--8<-- "includes/abbreviations.md"
--8<-- "includes/links.md"


[//begin]: # "Autogenerated link references for markdown compatibility"
[optimization]: optimization "Optimization"
[#stream-entrypoints]: streams "Streams"
[optimization#pruning-fields]: optimization "Optimization"
[relations]: relations "Related Objects"
[#Metadata-Watcher]: streams "Streams"
[//end]: # "Autogenerated link references"
