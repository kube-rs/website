# The Application

The **application** is a Rust application manages a [Controller]. It needs a [[reconciler]] that will be called with entries of your chosen [[object]], and a few dependencies to deal with async streams, error handling, and upstream Kubernetes structs.

This document shows how to create a __minimal__ application, with the builtin `Pod` type as the main object, and a no-op reconciler.

## Requirements

You need a [newish version](/rust-version) of stable [Rust], and access to a Kubernetes cluster.

## Project Setup
We create a new rust project:

```sh
cargo new --bin ctrl
cd ctrl
```

add then install our dependencies:

```sh
cargo add kube --features=runtime,client,derive
cargo add k8s-openapi --features=latest
cargo add thiserror
cargo add tokio --features=macros,rt-multi-thread
cargo add futures
```

<!-- do a content tabs feature here if it becomes free to let people tab between
This should give you a `[dependencies]` part in your `Cargo.toml` looking like:

```toml
kube = { version = "LATESTKUBE", features = ["runtime", "client", "derive"] }
k8s-openapi = { version = "LATESTK8SOPENAPI", features = ["latest"]}
tokio = { version = "1", features = ["macros", "rt-multi-thread"] }
futures = "0.3"
thiserror = "LATESTTHISERROR"
```
-->

This will populate some [`[dependencies]`](https://doc.rust-lang.org/cargo/reference/specifying-dependencies.html) in your `Cargo.toml` file.

### Dependencies

- [kube] :: with the controller `runtime`, Kubernetes `client` and a `derive` macro for custom resources
- [k8s-openapi] :: structs for core Kubernetes resources at the `latest` supported [[kubernetes-version]]
- [thiserror] :: typed error handling
- [futures] :: async rust abstractions
- [tokio] :: supported runtime for async rust features

Additional dependencies are useful, but we will go through these later as we add more features.

!!! warning "Alternate async runtimes"

    `kube` depends on [tokio] for its `time`, `signal` and `sync` features. Trying to swap to an alternate runtime is neither recommended, nor practical.

### Setting up errors

A full `Error` enum is the most versatile approach:

```rust
#[derive(thiserror::Error, Debug)]
pub enum Error {}

pub type Result<T, E = Error> = std::result::Result<T, E>;
```

### Define the object

Create or import the [[object]] that you want to control into your `main.rs`.

For the purposes of this demo we will import [Pod]:

```rust
use k8s_openapi::api::core::v1::Pod;
```

### Seting up the controller

This is where we will start defining our `main` and glue everything together:

```rust
#[tokio::main]
async fn main() -> Result<(), kube::Error> {
    let client = Client::try_default().await?;
    let pods = Api::<Pod>::all(client);

    Controller::new(pods.clone(), Default::default())
        .run(reconcile, error_policy, Arc::new(()))
        .for_each(|_| futures::future::ready(()))
        .await;

    Ok(())
}
```

This creates a [Client], a Pod [Api] object (for all namespaces), and a [Controller] for the full list of pods defined by a default [watcher::Config].

We are not using [[relations]] here, this only schedules reconciliations when a pod changes.

### Creating the reconciler

You need to define at least a basic `reconcile` fn

```rust
async fn reconcile(obj: Arc<Pod>, ctx: Arc<()>) -> Result<Action> {
    println!("reconcile request: {}", obj.name_any());
    Ok(Action::requeue(Duration::from_secs(3600)))
}
```

and an error handler to decide what to do when `reconcile` returns an `Err`:

```rust
fn error_policy(_object: Arc<Pod>, _err: &Error, _ctx: Arc<()>) -> Action {
    Action::requeue(Duration::from_secs(5))
}
```

To make this reconciler useful, we can reuse the one created in the [[reconciler]] document, on a custom [[object]].

## Checkpoint

If you copy-pasted everything above, and fixed imports, you should have a `main.rs` with this:

```rust
use std::{sync::Arc, time::Duration};
use futures::StreamExt;
use k8s_openapi::api::core::v1::Pod;
use kube::{
    Api, Client, ResourceExt,
    runtime::controller::{Action, Controller}
};

#[derive(thiserror::Error, Debug)]
pub enum Error {}
pub type Result<T, E = Error> = std::result::Result<T, E>;

#[tokio::main]
async fn main() -> Result<(), kube::Error> {
    let client = Client::try_default().await?;
    let pods = Api::<Pod>::all(client);

    Controller::new(pods.clone(), Default::default())
        .run(reconcile, error_policy, Arc::new(()))
        .for_each(|_| futures::future::ready(()))
        .await;

    Ok(())
}

async fn reconcile(obj: Arc<Pod>, ctx: Arc<()>) -> Result<Action> {
    println!("reconcile request: {}", obj.name_any());
    Ok(Action::requeue(Duration::from_secs(3600)))
}

fn error_policy(_object: Arc<Pod>, _err: &Error, _ctx: Arc<()>) -> Action {
    Action::requeue(Duration::from_secs(5))
}
```

## Developing

At this point, you are ready `cargo run` the app and see if it works against a Kubernetes cluster.

### Cluster Setup

> If you already have a cluster, skip this part.

We will develop locally against a `k3d` cluster (which requires `docker` and `kubectl`).

Install the [latest k3d release](https://k3d.io/#releases), then run:

```sh
k3d cluster create kube --servers 1 --agents 1 --registry-create kube
```

If you can run `kubectl get nodes` after this, you are good to go. See [k3d/quick-start](https://k3d.io/#quick-start) for help.

### Local Development

You should now be able to `cargo run` and check that you can successfully connect to your cluster.

You should see an output like the following:

```
reconcile request: helm-install-traefik-pxnnd
reconcile request: helm-install-traefik-crd-8z56p
reconcile request: traefik-97b44b794-wj5ql
reconcile request: svclb-traefik-5gmsm
reconcile request: coredns-7448499f4d-72rvq
reconcile request: metrics-server-86cbb8457f-8fct5
reconcile request: local-path-provisioner-5ff76fc89d-4x86w
reconcile request: svclb-traefik-q8zkw
```

Implying you get reconcile requests for every pod in your cluster (cross reference with `kubectl get pods --all`).

If you now edit a pod (via `kubectl edit pod traefik-xxx` and make a change), or create a new pod, you should immediately get a reconcile request.

**Congratulations**. You have __technically__ built a kube controller.

!!! note "Where to Go From Here"

    You have created the [[application]] using a trivial reconciler and a builtin object. See the [[object]] and [[reconciler]] chapters to change it into something more useful. The documents under __Concepts__ on the left navigation menu shows the core concepts that are instrumental to help create the right abstraction.

### Useful Dependencies

The following dependencies are **already used** transitively **within kube** that may be of use to you. Use of these will generally not inflate your total build times due to already being present in the tree:

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


--8<-- "includes/abbreviations.md"
--8<-- "includes/links.md"

[//begin]: # "Autogenerated link references for markdown compatibility"
[reconciler]: reconciler "The Reconciler"
[object]: object "The Object"
[kubernetes-version]: ../kubernetes-version "kubernetes-version"
[relations]: relations "Related Objects"
[testing]: testing "Testing"
[security]: security "Security"
[observability]: observability "Observability"
[optimization]: optimization "Optimization"
[streams]: streams "Streams"
[//end]: # "Autogenerated link references"
