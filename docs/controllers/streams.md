# Streams

This chapter is about the the `unstable-runtime` streams interface for controllers. It is expanding on the api documentation for

- [Controller::for_stream] - analogue for `Controller::new`
- [Controller::watches_stream] - analogue for `Controller::watches`
- [Controller::owns_stream] - analogue for `Controller::owns`

to give more substantial guidance on [[optimization]].

## Availability

By **default**, [watcher] streams are **implicitly configured** within the [Controller], but using the controller streams interface setup introduced in [kube 0.81](https://github.com/kube-rs/kube/releases/tag/0.81.0) you can **explicitly setup** all the [watcher] stream for more precise targeting:

```rust
Controller::for_stream(main_stream, reader)
    .owns_stream(owned_custom_stream, cfg)
    .watches_stream(watched_custom_stream, cfg)
```

where the various stream variables would be created from either [watcher], or [metadata_watcher] with some filters/flatteners applied.

!!! warning "The controller streams interface is unstable"

    Currently plugging streams into [Controller] requires the `kube/unstable-runtime` feature. This interface is planned to be stabilized in a future release.

## Terminology

- **flattened stream** :: a stream that's been through [EventFlatten] via one of `WatchStreamExt::touched_objects`, `WatchStreamExt::applied_objects`
- **raw event stream** :: a raw [watcher] stream producing un-flattened [watcher::Event] objects

The significant difference between them is that the **user** and the [Controller] generally wants to interact with a **flattened stream**, but a [reflector] needs a **raw event stream** to be able to safely replace its contents.

## Inputs
To swap out one of the input streams you need to:

1. create a watcher stream with backoff
2. flatten the stream
3. replace the interface

The `Controller` will still poll all the various input streams, so it's only necessary for you to initialise them and setup the stream flow.

### Main Stream
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

leaving additionally the `reader` in your hands should you need it (obviating the non-stream requirement to call to `Controller::store`).

### Owned Stream
As per [[relations]], this requires your owned objects to have owner refrences back to your main object (`cr`):

```diff
 let cfg_owned = watcher::Config::default();
 let cfg_cr = watcher::Config::default();
 let cr: Api<MyCustomResource> = Api::all(client.clone());
 let owned_api: Api<Deployment> = Api::default_namespaced(client);
+let deploys = watcher(owned_api, cfg_owned).default_backoff().applied_objects();

 Controller::new(cr, cfg_cr)
-    .owns(owned_api, cfg_owned)
+    .owns_stream(deploys)
```

Usually combines very cleanly with [[#Metadata-Watcher]] usage due to the reverse mapping (say from `Deployment` to `MyCustomResource`) being done entirely with metadata properties.

### Watched Stream
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

## Metadata Watcher

A [metadata_watcher] is a [watcher] analogue that using the **metadata api** that **only** returns [TypeMeta] (`.api_version` + `.kind`) + [ObjectMeta] (`.metadata`).

This can generally be used as a **drop-in replacement** for [watcher] provided you do not need data in `.spec` or `.status`.

This means less IO, and less memory usage (especially if you are funnelling the data into a [reflector]). See the **[[optimization]] chapter** for details.

You can generally **replace** `watcher` with `metadata_watcher` in the examples above as:

```diff
# General change:
-let stream =          watcher(api, cfg).applied_objects();
+let stream = metadata_watcher(api, cfg).applied_objects();

# Same change inside a reflector:
-let stream = reflector(writer,          watcher(api, cfg)).applied_objects();
+let stream = reflector(writer, metadata_watcher(api, cfg)).applied_objects();
```

But note this changes the stream signature slightly; returning a wrapped [PartialObjectMeta]. This type change matters mostly if you are using metadata watchers on the main stream.

!!! warning "Metadata Watchers on Main Stream"

    Using [metadata_watcher] on the main stream (using `Controller::for_stream`) changes the `reconcile` / `error_policy` type signature from returning objects of form `Arc<K>` to `Arc<PartialObjectMeta<K>>`:

    ```diff
    -async fn reconcile(_: Arc<Deployment>, _: Arc<()>) ...
    +async fn reconcile(_: Arc<PartialObjectMeta<Deployment>>, _: Arc<()>) ...
    -fn error_policy(_: Arc<Deployment>, _: &kube::Error, _: Arc<()>) ...
    +fn error_policy(_: Arc<PartialObjectMeta<Deployment>>, _: &kube::Error, _: Arc<()>) ...
    ```

    This means the object you get in your reconciler is just a partial object with only `.metadata`. You can call `api.get()` inside `reconcile` to get a full object if needed.

## Stream Mutation
It is possible to modify or filter the input streams before passing them on. This is usually done to feed the downstream controller less data so that it either triggers less frequently or for memory [[optimization]] reasons.

### Predicates
Using [predicates], we can **filter out** events from a stream where the **last value** of a particular property is **unchanged**. This is done internally by storing hashes of the given property(ies), and can be chained onto a **flattened** stream:

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
You can use `Event::modify` to modify raw objects in flight before they are passed on to a reflector or controller. This is usually done to minimise [reflector] memory consumption.

```rust
let stream = watcher(pods, cfg).map_ok(|ev| {
    ev.modify(|pod| {
        pod.managed_fields_mut().clear();
        pod.status = None;
    })
});
let (reader, writer) = reflector::store::<Pod>();
let rf = reflector(writer, stream).applied_objects();
```

## Multi Stream Example
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
[relations]: relations "Related Objects"
[#Metadata-Watcher]: streams "Streams"
[//end]: # "Autogenerated link references"