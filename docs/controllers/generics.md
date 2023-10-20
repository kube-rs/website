# Generics

This chapter contains tips and tricks for re-using generic reconcilers.

## Generic Reconcilers
It is possible to create generic reconcilers by abstracing away the underlying type by using either [DynamicObject] or [PartialObjectMeta].

This is a useful technique for controllers that need to do _the same thing_ to a bunch of resources, like for instance adding consistent labels / annotations.

### PartialObjectMeta

This is the easiest and cheapest way to create a generic reconciler because it still retains type information, and you do not have to devolve into a fully dynamic api.

You can create generic reconcilers:

```rust
pub async fn reconcile<K>(obj: Arc<PartialObjectMeta<K>>, ctx: Arc<Context>)
-> Result<Action>
where
    K: Resource<Scope = NamespaceResourceScope, DynamicType = ()>
        + Clone
        + DeserializeOwned
        + Debug,
{
    let kind = K::kind(&()).to_string();
    let ns = obj.namespace().unwrap();
    let object_name = obj.name_any();
    let api: Api<PartialObjectMeta<K>> = Api::namespaced(ctx.client, &ns);

    // example work; apply some labels to the object
    let patch: Patch<serde_json::Value> = get_standard_labels_for(&obj)?;
    let serverside = PatchParams::apply("labeler");
    api.patch(&object_name, &serverside, &patch).await?;

    Ok(Action::requeue(Duration::from_secs(5 * 60)))
}
```

The generic constraints on the associated type of the [Resource] here means this is a __namespaced__ resource (hence the unwrap). You could remove this bound (or change it for a cluster scoped only bound), but then you could not unwrap.

The `DynamicType = ()` constraint is to indicate that this is one of the normal statically generated api types that we have api information for at the type level (i.e. they come from `k8s-openapi`).

For information about the resource we rely on the generic [Resource] and [ResourceExt] traits which is implemented by [PartialObjectMeta].

!!! note "Diverging Logic"

    You will only get access to metadata of the object doing this. This can be mitigated by doing a `match` on `kind` and creating a more specific `Api<K>` inside a match arm.


These reconcilers can be hooked up to a `Controller<K>` with another possibly generic fn.

```rust
async fn run_controller<K>(client: Client)
where
    K: Resource<Scope = NamespaceResourceScope, DynamicType = ()>
        + Clone
        + DeserializeOwned
        + Debug
        + Sync
        + Send
        + 'static,
{
    let kind = K::kind(&()).to_string();
    tracing::info!("Starting controller for {kind}");

    let api = Api::<K>::all(client.clone());
    let (reader, writer) = reflector::store();

    // controller main stream from metadata_watcher
    let stream = metadata_watcher(api, watcher::Config::default())
        .default_backoff()
        .modify(|x| {
            x.managed_fields_mut().clear(); // ResourceExt pruning
        })
        .reflect(writer)
        .applied_objects()
        .predicate_filter(predicates::generation);

    Controller::for_stream(stream, reader)
        .shutdown_on_signal()
        .run(reconcile, error_policy, Arc::new(Context::new(client)))
        .for_each(|_| futures::future::ready(()))
        .await;

    warn!("controller for {kind} shutdown");
}
```

This example assumes no [[relations]] between the main controller [[object]], so that each controller can be started in isolation without worrying about inefficiencies in stream-reuse (see [[streams]]). It also relies on [WatchStreamExt] + [metadata_watcher] to apply a consistent stream setup, pruning, and predicates (see [[optimization]]).

We can start and control the lifecycle of all the controllers with a [tokio::try_join!]:

```rust
pub async fn run_all_controllers(client: Client) {
    let _ = tokio::join!(
        run_controller::<Deployment>(client.clone()),
        run_controller::<DaemonSet>(client.clone()),
        run_controller::<StatefulSet>(client.clone()),
        run_controller::<CronJob>(client.clone()),
    );
    info!("controllers all exited");
}
```

This returns when **all** controller fns return. This only happens once [shutdown_on_signal] has propagated through all the controllers because the `run_controller` fn is here infallible.


--8<-- "includes/abbreviations.md"
--8<-- "includes/links.md"
