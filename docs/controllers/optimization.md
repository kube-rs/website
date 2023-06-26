# Optimization

This document aims to help optimize various factors of resource consumption by controllers, and it will effectively be a guide on how to reduce the usage of your [watcher] streams to simplify things for downstream consumers.

## Watcher Streams in Controllers

By **default**, [watcher] streams are **implicitly configured** within the [Controller], but using the controller streams interface setup introduced in [kube 0.81](https://github.com/kube-rs/kube/releases/tag/0.81.0) you can **explicitly setup** all the [watcher] stream for more precise targeting:

```rust
let cfg = watcher::Config { RESTRICTIONS };
let stream = reflector(writer, SOME_WATCHER(cfg))
Controller::for_stream(stream, reader);
```

As this document will show, there are various ways to put restrictions on your watcher (and there are also two main types of watchers), but the central premise herein is that **controllers benefit from customizing the input stream** and we will show how to do these configurations.

!!! warning "The controller streams interface is unstable"

    Currently plugging streams into [Controller] requires the `kube/unstable-runtime` feature. This interface is planned to be stabilized in a future release.

The controller streams interface is comprised of [Controller::for_stream], and [Controller::watches_stream] and [Controller::owns_stream], which are stream input analogues for the commonly advertised `Controller::new`, `Controller::watches`, and `Controller::owns` (respectively) interfaces.

## Watcher Optimization

One of the biggest contributor to activity in a [Controller] is the constant, long-polling watch of the [[object]] and every related object by the use of multiple [watcher] streams.

By themselves, the optimizations listed herein for watchers are generally for reducing IO or networked traffic. However, when used in combination with [reflector] caches they also become memory optimizations.


### Reducing Number of Watched Objects
The default `watcher::Config` will watch every object in the [Api] scope you configured:

- `Api::namespaced` or `Api::default_namespaced` -> all objects in that namespace
- `Api::all` -> all cluster scoped objects (or all objects in all namespaces)

This can be limited to just a subset of namespaces, or other properties on the objects. For example, field selectors can be used to limit to a selection of known names:

```rust
let cfg = watcher::Config::default().fields(&format!("metadata.name={name}"));
```

This can be comma-delimited for more names, and similarly you you can also comma deliminate an exclusion list on names or namespaces:

```rust
let ignoring_system_namespaces = [
    "carousel",
    "cattle-fleet-system",
    "cattle-impersonation-system",
    "cattle-monitoring-system",
    "cattle-system",
    "fleet-system",
    "gatekeeper-system",
    "kube-node-lease",
    "kube-public",
    "kube-system",
]
.into_iter()
.map(|ns| format!("metadata.namespace!={ns}"))
.collect::<Vec<_>>()
.join(",");
let cfg = watcher::Config::default().fields(&ignoring_system_namespaces);
```

!!! note "Field Selector Limitations"

    Due to [field-selector](https://kubernetes.io/docs/concepts/overview/working-with-objects/field-selectors/) limitations, you cannot filter on arbitrary fields, nor can you do set complements (need to enumerate explicitly).

If you find that field-selectors are too constrictive for your set of objects, the problem can generally be solved using by [explicitly labelling](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/) the objects you care about and use label selectors instead:

```rust
let cfg = Config::default().labels("environment in (production, qa)");
```

### Watching Metadata Only

Generally, **Kubernetes will return all fields** for an object when doing a watch, so while the main tool at our disposal to reduce networked traffic is to reduce the number of watched objects, there is one trick available:

We can ask Kubernetes to only return [TypeMeta] (`.api_version` + `.kind`) + [ObjectMeta] (`.metadata`) in our watches and list calls using `Api::watch_metadata` or the stream analogue [metadata_watcher]; a drop-in replacement for [watcher]:

```rust
let cfg = watcher::Config::default().fields(&ignoring_system_namespaces);
let stream = reflector(writer, metadata_watcher(api, cfg)).applied_objects();
```

While this will not work in all cases (if you need more data than metadata), it is a big improvement when it is feasible.

Given that metadata is generally only responsible for a **fraction of the data** in dense objects - and generally receives even 2x benefits for more sparse objects (see also [[#pruning-fields]]) - swapping to metadata_watchers can **significantly reduce the reflector memory footprint**.

TODO: panel snapshot.

This is a networked simplification and will also **reduce the amount of networked traffic** the controller is responsible for by commensurate amounts.

TODO: panel snapshot.

### Avoid the List Spike

At time of writing, every permanent watch loop setup against kube-apiserver requires a `list` call (to initialise) followed by a long `watch` call starting at the given `resourceVersion` from `list`. De-syncs can happen, and this would force a re-list to re-initialize (forcing a slew of old objects to be passed through controllers again).

This internal `list` call hides a problematic api usage; an unlimited `list` call. In large/busy clusters, retrieving all of objects in one call is very memory intensive (for both the apiserver and the controller). [#1209](https://github.com/kube-rs/kube/issues/1209) has more details.

A configuration for this is scheduled for 0.84 via https://github.com/kube-rs/kube/pull/1211, and require an opt-in for setting the page limit:

```rust
let cfg = watcher::Config::default().page_size_limit(50);
```

This should reduce the **peak memory footprint** of both the apiserver and your controller at the times the controller needs to do a re-list.

!!! note "Streaming List Alpha"

    The [1.27 alpha streaming-lists feature](https://kubernetes.io/docs/reference/using-api/api-concepts/#streaming-lists) may change things up in the future, but this is not currently supported by kube.

## Reflector Optimization

Unless you have another large in-memory cache or other similar memory users in your controller, the **primary contributor** to your controller's memory use is going to be the **mandatory reflector** for the main [[object]] as well as any other **optional reflectors** for related objects.

The memory usage of reflectors can be minimized by tweaking a number of properties:

1. Amount of objects watched (`watcher::Config`)
2. Asking for metadata only when applicable (`metadata_watcher`)
2. Pruning unnecessary fields before storing (modify + clear pre-storage)

We have already talked about the first two points ([[#Reducing Number of Watched Objects]] and [[#Watching Metadata Only]]) above as these have IO benefits for watchers on their own, but also cause memory usage reductions by forcing less stored objects/data.


### Pruning Fields
By default, the memory stored for each object is equivalent to what you get from asking `kubectl` for all objects matching your `ListParams`, but additionally asking for `--show-managed-fields` which `kubectl` hides from you by default, but is always part of any underlying api based request.

Most controllers do not need to know about the specifics of these, and they should usually be pruned pre-insertion:

```rust
let api: Api<Pod> = Api::default_namespaced(client);
let stream = watcher(pods, watcher::Config::default()).map_ok(|ev| {
    ev.modify(|pod| {
        // memory optimization for our store - we don't care about fields/annotations/status
        pod.managed_fields_mut().clear();
        pod.annotations_mut().clear();
        pod.status = None;
    })
});
let (reader, writer) = reflector::store::<Pod>();
let rf = reflector(writer, stream).applied_objects();
```

In general, this __can be done for all the fields you do not care about__. Above we also clear out the status object and annotations entirely pre-storage.

!!! warning "Pruning ObjectMeta"

    Do not prune **everything** from [ObjectMeta] as `kube::runtime` relies on being able to see `.metadata.name`, `.metadata.resource_version` and `metadata.namespace` from [watcher] streams in controllers and reflector stores.

Note that pruning will not reduce your network traffic. All object data retrieved from the watcher is always transmitted over the wire.

## Reconciler Optimization

The [[reconciler]] is the generally the entry-point for your business logic, so we cannot give too much blanket advice on optimizing this, but we can give a few pointers.

As a general recommendation; instrumenting standard metrics ([[observability#what-metrics]]) on your reconciler, and sending traces of more complicated microservice interactions to a trace collector ([[observability#instrumenting]]) are good [[observability]] practices, but outside the scope of this document.

### Repeatedly Triggering Yourself

AKA the problem that you will most easily run into; a **reconciler that modifies the status** (say) of its main [[object]] will cause a change in that object that is picked up by the [Controller]'s watcher loop, and will be **fed back into the reconciler**.

This is normally not a problem, because **if** your status patch that causes this change is **idempotent**, it will **only happen once**. The problem is when you start putting non-deterministic values inside the the `.status` resource (e.g. timestamps rather than hashes).

In such cases, the **controller will spin forever** on such objects.

!!! note "Detecting spinlocks"

    Spinlocks are usually noticeable quickly by just running the controller locally and watching logs for one object, or having a plot graph on your reconciler rate ([[observability#what-metrics]]) in `grafana`. You should expect about 1 to 5+ reconciles every `1/(your requeue time)` growing with the number of affected objects and self-interaction.

The two ways to avoid reconciler re-triggering are:

1. don't patch in non-deterministic values to your object (breaks idempotency)
2. filter out changes to irrelevant parts of your object

These approaches are **both recommended** because they both have independent merits;

1. idempotency is good, and it avoids the spin problem the "good practice way"
2. early filtering can allow for more precise reconcile bypasses with less code complexity, and allow opt-in non-determinism (such as timestamp fields)

Watch events can be filtered out early using **predicates** with [WatchStreamExt::predicate_filter], and passing on these pre-filtered streams to controllers:

```rust
let deploys: Api<Deployment> = Api::default_namespaced(client);
let changed_deploys = watcher(deploys, watcher::Config::default())
    .applied_objects()
    .predicate_filter(predicates::generation);
```

!!! warning "Predicates are unstable"

    Predicates are a new feature in some flux with the last change in 0.84. They require one of the `unstable-runtime` feature flags.

## Impossible Optimizations

We leave a list of **currently impossible** (or technically infeasible) controller optimisation problems here and link to issues for transparency and in the hope that they will be tackled in the future.

- [Sharing streams between **multiple controllers**](https://github.com/kube-rs/kube/issues/1080) (can only configure so far)
- [Waiting for a store to be ready](https://github.com/kube-rs/kube/issues/1226)

## Summary

As a short summary, here are the main listed optimization and the effect you should expect to see from utilising them.

| Optimization Type  | Target Reduction   |
| ------------------ | ------------------ |
| metadata_watcher   | IO + Memory        |
| watcher selectors  | IO + Memory        |
| watcher page size  | Peak Memory        |
| pruning            | Memory Only        |
| predicates         | Memory + Code Size |

It is important to note that **all of these are watcher tweaks**.
The target reductions above can all be granted by passing more precise streams to your controller.

--8<-- "includes/abbreviations.md"
--8<-- "includes/links.md"

[//begin]: # "Autogenerated link references for markdown compatibility"
[object]: object "The Object"
[#pruning-fields]: optimization "Optimization"
[#Reducing Number of Watched Objects]: optimization "Optimization"
[#Watching Metadata Only]: optimization "Optimization"
[reconciler]: reconciler "The Reconciler"
[observability#what-metrics]: observability "Observability"
[observability#instrumenting]: observability "Observability"
[observability]: observability "Observability"
[//end]: # "Autogenerated link references"
