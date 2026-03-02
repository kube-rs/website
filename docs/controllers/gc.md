# Garbage Collection

This chapter covers the two main forms of [Kubernetes garbage collection](https://kubernetes.io/docs/concepts/architecture/garbage-collection/) and when + how to use them with controllers.

## Owner References
When your object __owns__ another resource living inside Kubernetes, you can put an owner reference on the child object so that when you delete the parent object, Kubernetes will automatically initiate cleanup of the dependents.

This is explained in more detail in [Kubernetes.io :: Owners and Dependents](https://kubernetes.io/docs/concepts/overview/working-with-objects/owners-dependents/).

!!! note "OwnerReferences are for children"

    You should use owner references on generated child objects that have a clear owner object within Kubernetes.

To successfully use owner references you need to:

1. insert the reference on any object you are creating from your reconciler
2. mark the children as watchable through owner [[relations]]

### Owner Reference Example
In the [configmapgen_controller example](https://github.com/kube-rs/kube/blob/main/examples/configmapgen_controller.rs), the controller creates a `ConfigMap` from a contrived `ConfigMapGenerator` custom resource ([cmg crd](https://github.com/kube-rs/kube/blob/main/examples/configmapgen_controller_crd.yaml)). The [example's reconciler](https://github.com/kube-rs/kube/blob/83368df52a4845e06edbb9b4b3246c3807bb711a/examples/configmapgen_controller.rs#L37-L73) for the `ConfigMapGenerator` objects insert the `owner_reference` into the generated `ConfigMap`:

```rust
let oref = generator.controller_owner_ref(&()).unwrap();
let cm = ConfigMap {
    metadata: ObjectMeta {
        name: generator.metadata.name.clone(),
        owner_references: Some(vec![oref]),
        ..ObjectMeta::default()
    },
    data: Some(contents),
    ..Default::default()
};
```

using [`Resource::controller_owner_ref`](https://docs.rs/kube/latest/kube/trait.Resource.html#method.controller_owner_ref). It then [marks](https://github.com/kube-rs/kube/blob/83368df52a4845e06edbb9b4b3246c3807bb711a/examples/configmapgen_controller.rs#L108C11-L109) `ConfigMap` as a dependent type to watch for via [[relations]]:

```rust
Controller::new(cmgs, watcher::Config::default())
    .owns(cms, watcher::Config::default())
```

## Finalizers
A finalizer is a marker on a root object that indicates that a controller will perform cleanup if the object is ever deleted. Kubernetes will block the object from being deleted __until__ the controller completes the cleanup. The controller is supposed to remove this marker in the finalizer list when cleanup is done, so that Kubernetes is free to proceed with deletion.

This is explained in more detail in [Kubernetes.io :: Finalizers](https://kubernetes.io/docs/concepts/overview/working-with-objects/finalizers/).

!!! note "Finalizers mark the need for controller cleanup"

    You should mark objects with a finalizer if it needs external cleanup to run in the event it is deleted.

The main way to use finalizers with controllers is to define a unique finalizer name (many controllers can finalize an object) and make the [finalizer] helper manage it. The finalizer helper is designed to be used within a reconciler and split the work depending on the state we are in:

- Has a deletion occurred, and do we need to clean up? If so, we are in the `Event::Cleanup` arm
- Has no deletion been recorded? Then we are in the normal `Event::Apply` arm

!!! warning "Finalizers can prevent objects from being deleted"

    If your controller is down, deletes will be delayed until the controller is back.

### Finalizer Example

In the [secret_syncer example](https://github.com/kube-rs/kube/blob/main/examples/secret_syncer.rs), the controller manages an artificially external secret resource (in reality the example puts it in Kubernetes, but please ignore that) on changes to a `ConfigMap`.

Because we cannot normally watch external resources through Kubernetes watches, we have not setup any [[relations]] for the secret. Instead, we use the [finalizer] helper in a reconciler (here as a lambda), and delegate to two more specific reconcilers:

```rust
|cm, _| {
    let ns = cm.meta().namespace.as_deref().ok_or(Error::NoNamespace).unwrap();
    let cms: Api<ConfigMap> = Api::namespaced(client.clone(), ns);
    let secrets: Api<Secret> = Api::namespaced(client.clone(), ns);
    async move {
        finalizer(
            &cms,
            "configmap-secret-syncer.nullable.se/cleanup",
            cm,
            |event| async {
                match event {
                    Event::Apply(cm) => apply(cm, &secrets).await,
                    Event::Cleanup(cm) => cleanup(cm, &secrets).await,
                }
            },
        )
        .await
    }
}
```

in this example, the `cleanup` fn is deleting the secret (which you should imagine as not living inside Kubernetes), and the `apply` fn looks like how your `reconcile` fn normally would look like.

If you run this example locally and apply the [example configmap](https://github.com/kube-rs/kube/blob/main/examples/secret_syncer_configmap.yaml), you will notice you cannot `kubectl delete` it the object once it has been reconciled once without keeping the controller running; the `cleanup` is guaranteed to run.

## Default Cleanup

Not every controller needs extra cleanup in one of the two forms above.

If you are satisfied with your object being removed if someone runs `kubectl delete`, then that's all the cleanup you need.

You only need these extra forms of garbage collection when you are directly in charge of the lifecycle of other resources - inside or outside Kubernetes.

## Summary

In short, if you need to:

1. __Automatically__ garbage collect child objects? use `ownerReferences`
2. __Programmatically__ garbage collect dependent resources? use `finalizers`

If you are generating resources both inside and outside Kubernetes, you might need both kinds of cleanup (or make a bigger `cleanup` finalizer routine).


--8<-- "includes/abbreviations.md"
--8<-- "includes/links.md"
