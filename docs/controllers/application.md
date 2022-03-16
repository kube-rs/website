# The Application

The **application** starts the [Controller] and links it up with the [[reconciler]] for your [[object]].

## Plan

this document should describe what we plan on describing (super simple pod controller from a CRD), how to glue it together
while it's in the main 3 documents, it needs to be an overview doucment (as it contains the other two in some sense)

should link to sub-sections where we take shortcuts here (different objects, ~~related objects~~, controller options, packaging)

> We will be creating a controller for a subset of Pods with a `category` label. This controller will watch these pods and ensure they are in the correct state, updating them if necessary.

## Requirements

We will assume that you have latest **stable** [rust] installed, along with [cargo-edit]:

## Project Setup

```sh
cargo new --bin ctrl
cd ctrl
```

add then install `kube`, `k8s-openapi` and `tokio` using [cargo-edit]:

```sh
cargo add kube --features=runtime,client,derive
cargo add k8s-openapi --features=v1_23
cargo add tokio --features=macros,rt-multi-thread
cargo add futures
```

<!-- do a content tabs feature here if it becomes free to let people tab between
This should give you a `[dependencies]` part in your `Cargo.toml` looking like:

```toml
kube = { version = "LATESTKUBE", features = ["runtime", "client", "derive"] }
k8s-openapi = { version = "LATESTK8SOPENAPI", features = ["v1_23"]}
tokio = { version = "1", features = ["macros", "rt-multi-thread"] }
futures = "0.3"
```
-->

This will populate some [`[dependencies]`](https://doc.rust-lang.org/cargo/reference/specifying-dependencies.html) in your `Cargo.toml` file.

### Main Dependencies

The [kube] dependency is what we provide. It's used here with its controller `runtime` feature, its Kubernetes `client` and the `derive` macro for custom resources.

The [k8s-openapi] dependency is needed if using core Kubernetes resources.

The [futures] dependency provides helpful abstractions when working with asynchronous rust.

The [tokio] runtime dependency is needed to use async rust features, and is the supported way to use futures created by kube.

!!! warning "Alternate async runtimes"

    We depend on `tokio` for its `time`, `signal` and `sync` features, and while it is in theory possible to swap out a runtime, you would be sacrificing the most actively supported and most advanced runtime available. Avoid going down this alternate path unless you have a good reason.

Additional dependencies are useful, but we will go through these later as we add more features.

### Define the

Import the [[object]] that you want to control into your `main.rs`.

For the purposes of this demo we are going to use [Pod] (hence the explicit `k8s-openapi` dependency), and because we don't want to control all pods, we will limit to pods with our own `category: weird` label using [ListParams].

```rust
use k8s_openapi::api::core::v1::Pod;
let params = ListParams::default().labels("category=weird");
```

### Seting up the controller

This is where we will start defining our `main` and glue everything together:

```rust
#[tokio::main]
async fn main() -> Result<()> {
    let client = Client::try_default().await?;
    let pods = Api::<Pod>::all(client);
    let params = ListParams::default().labels("category=weird");

    Controller::new(pods.clone(), params)
        .run(reconcile, error_policy, Context::new(Data { pods }))
        .for_each(|_| futures::future::ready(()))
        .await;

    Ok(())
}
```

This creates a [Client], a Pod [Api] object, and a [Controller] for the subset of pods defined by the [ListParams].

We are not using [[relations]] here, so we merely tell the controller to call reconcile when our owned subset of pods changes.

### Creating the reconciler

We will start with a noop `reconcile` fn
```rust
async fn reconcile(object: Arc<Pod>, data: Context<Data>) ->
    Result<ReconcilerAction, Error>
{
    let pods = ctx.get_ref().pods.clone();
    // object.annotations_mut(). TODO: edit annotations
    // TODO: save via entry api?
    // Done.

    Ok(ReconcilerAction {
        requeue_after: Some(Duration::from_secs(3600 / 2)),
    })
}
```

and a `noop` error handler:

```rust
fn error_policy(_error: &Error, _ctx: Context<Data>) -> ReconcilerAction {
    ReconcilerAction {
        requeue_after: Some(Duration::from_secs(5)),
    }
}
```

TODO: discuss saving triggering reconciles

## Extra Dependencies

The following dependencies are **already used** transitively **within kube** and will generally not inflate your full dependencies list by adding:

- [tracing]
- [futures]
- [k8s-openapi]
- [serde]
- [serde_json]
- [serde_yaml]
- [tower]
- [tower-http]
- [hyper]
- [thiserror]

These in turn also pull in their own dependencies (and tls features, depending on your tls stack), consult [cargo-tree] for help minimizing your dependency tree.

## Deploying

### Containerising

Options:

- rust official image as multi-stage builder
- musl + distroless

TODO: caching caveats (links only)

### Developing

TODO: dev workflow via `k3d` + `tilt` or straight `cargo run` possibilities via `Client::try_default`

### CI

TODO:

- clippy
- docker build with cache

--8<-- "includes/abbreviations.md"
--8<-- "includes/links.md"

[//begin]: # "Autogenerated link references for markdown compatibility"
[reconciler]: reconciler "The Reconciler"
[object]: object "The Object"
[relations]: relations "Relations"
[//end]: # "Autogenerated link references"
