
# Related Objects

A [Controller] needs to specify related resources if changes to them are meant to trigger the [[reconciler]].

These relations are generally set up with [Controller::owns], but we will go through the different variants below.

## Owned Relation

The [Controller::owns] relation is the most straight-forward and most ubiquitous one. One object controls the lifecycle of a child object, and cleanup happens automatically via [[gc#Owner-References]].

```rust
let cmgs = Api::<ConfigMapGenerator>::all(client.clone());
let cms = Api::<ConfigMap>::all(client.clone());

Controller::new(cmgs, watcher::Config::default())
    .owns(cms, watcher::Config::default())
```

This [configmapgen example](https://github.com/kube-rs/kube/blob/main/examples/configmapgen_controller.rs) uses one custom resource `ConfigMapGenerator` whose controller is in charge of the lifecycle of the child `ConfigMap`.

- What happens if we delete a `ConfigMapGenerator` instance here? Well, there will be a `ConfigMap` with [ownerReferences] matching the `ConfigMapGenerator` so Kubernetes will automatically cleanup the associated `ConfigMap`.
- What happens if we modify the **managed** `ConfigMap`? The Controller sees a change and associates the change with the owning `ConfigMapGenerator`, ultimately triggering a reconciliation of the root `ConfigMapGenerator`.

This relation relies on [ownerReferences] being created on the managed/owned objects for Kubernetes automatic cleanup, and the [Controller] relies on it for association with its owner.

!!! note "Streams Variant"

    To configure or share the [watcher] for the owned resource, see [[streams#owned-stream]].

## Watched Relations

The [Controller::watches] relation is for related Kubernetes objects **without** [ownerReferences], i.e. without a standard way for the controller to map the object to the root object. Thus, you need to define this mapper yourself:

```rust
let main = Api::<MainObj>::all(client);
let related = Api::<RelatedObject>::all(client);

let mapper = |obj: RelatedObject| {
    obj.spec.object_ref.map(|oref| {
        ReconcileRequest::from(oref)
    })
};

Controller::new(main, watcher::Config::default())
    .watches(related, watcher::Config::default(), mapper)
```
<!-- TODO: ReconcileRequest::from sets reason to Unknown, needs a method to set reason, ReconcileReason -> controller::Reason -->

In this case, we are extracting an object reference from the spec of our object. Regardless of how you get the information, your mapper must return an iterator of [ObjectRef] for the root object(s) that must be reconciled as a result of the change.

As a theoretical example; every [HPA](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/) object bundles a scale ref to the workload, so you could use this to build a Controller for `Deployment` using HPA as a watched object.

!!! note "Streams Variant"

    To configure or share the [watcher] for watched resource, see [[streams#watched-stream]].

## External Relations

Free-form relations to external apis often serve to lift an external resource into your cluster via either a `ConfigMap` or a CRD (see the [tradeoff table](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/#should-i-use-a-configmap-or-a-custom-resource)). This relation can go in both directions.

### External Watches
If you want changes on an external API to cause changes in the cluster, you will need to a way to stream changes from the external api.

The _change events_ must be provided as a `Stream<Item = ObjectRef>` and passed to [Controller::reconcile_on]. As an example:

```rust
struct ExternalObject {
    name: String,
}
let external_stream = watch_external_objects().map(|ext| {
    ObjectRef::new(&ext.name).within(&ns)
});

Controller::new(Api::<MyCr>::namespaced(client, &ns), Config::default())
    .reconcile_on(external_stream)
```

In this case, we have some opaque `fn watch_external_objects()` which here returns `-> impl Stream<Item = ExternalObject>`. It is meant to return changes from the external API. Whenever a new item is found on the stream, the controller will reconcile the matching cluster object.

(The example assumes __matching names__ between the external resource and cluster resource, and a __fixed namespace__ for the cluster resources.)

!!! note "Streaming Interface"

    If you do not have a streaming interface (like if you are doing periodic HTTP GETs), you can wrap your data in a `Stream` via either [async_stream](https://docs.rs/async-stream/latest/async_stream/) or by using channels (say [tokio::sync::mpsc](https://docs.rs/tokio/latest/tokio/sync/mpsc/index.html), using the [Receiver](https://docs.rs/tokio/latest/tokio/sync/mpsc/struct.Receiver.html) side as a stream).

### External Writes
If you want to populate an external API from a cluster resource, you must update the external api from your [[reconciler]] (using the necessary client libraries for that API).

To avoid build-up of generated objects on the external side, you will want to use [[gc#finalizers]], to ensure the external resource gets _safely_ cleaned up on `kubectl delete`.

## Summary

Depending on what type of child object and its relation with the main [[object]], you will need the following setup and cleanup:

| Child              | Controller relation  | Setup                       |  Cleanup          |
| ------------------ | -------------------- | --------------------------- | ----------------- |
| Kubernetes object  | Owned                | [Controller::owns]          | [ownerReferences] |
| Kubernetes object  | Related              | [Controller::watches]       | n/a               |
| External API       | Managed              | [Controller::reconcile_on]  | [finalizers]      |
| External API       | Related              | [Controller::reconcile_on]  | n/a               |

--8<-- "includes/abbreviations.md"
--8<-- "includes/links.md"

[//begin]: # "Autogenerated link references for markdown compatibility"
[reconciler]: reconciler "The Reconciler"
[object]: object "The Object"
[//end]: # "Autogenerated link references"
