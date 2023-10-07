
# Related Objects

A [Controller] needs to specify related resources if changes to them is meant to trigger the [[reconciler]].

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
<!-- TODO: ReconcileRequest::from sets reason to Unknow, needs a method to set reason, ReconcileReason -> controller::Reason -->

In this case we are extracing an object reference from the spec of our object. Regardless of how you get the information, your mapper must return an iterator of [ObjectRef] for the root object(s) that must be reconciled as a result of the change.

As a theoretical example; every [HPA](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/) object bundles a scale ref to the workload, so you could use this to build a Controller for `Deployment` using HPA as a watched object.

!!! note "Streams Variant"

    To configure or share the [watcher] for watched resource, see [[streams#watched-stream]].

## External Relations

It is possible to be dependent on some external api that you have semantically linked to your cluster, either as a managed resource or a source of information.

- If you want to populate an external API from a custom resource, you will want to use [finalizers] to ensure the api gets cleaned up on CRD deletion.
- If you want changes to the external API to trigger reconciliations, you will need to inject reconciliation requests as raw `ObjectRef`s.

To inject reconciliation requests to the [Controller] see [Controller::reconcile_on] or [Controller::reconcile_all_on]. Here's a contrieved example of the former:

```rust
let ns = "external-configs".to_string();
let externals = [ObjectRef::new("managed-cm1").within(&ns)];
let mut next_object = externals.into_iter().cycle();

// pretend 3rd party api that gives you periodic data:
let interval = tokio::time::interval(Duration::from_secs(60));
let external_stream = IntervalStream::new(interval).map(|_| {
    Ok(next_object.next().unwrap())
});
```

Here we cycle through a hardcoded list of named objects and sending the `next` ref through the reconciler at 60s interval (using [tokio_stream]'s `IntervalStream`), and the controller accepts this:

```rust
Controller::new(Api::<ConfigMap>::namespaced(client, &ns), Config::default())
    .reconcile_on(external_stream)
```

You would now now get Kubernetes changes + whatever custom stream data you wish to inject.

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
