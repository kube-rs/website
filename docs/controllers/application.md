# The Application

The **application** starts the [Controller] and links it up with the [[reconciler]] for your [[object]].

## Goal

This document shows the basics of creating a simple controller with a `Pod` as the main [[object]].

## Requirements

We will assume that you have latest **stable** [rust] installed, along with [cargo-edit]:

## Project Setup

```sh
cargo new --bin ctrl
cd ctrl
```

add then install `kube`, `k8s-openapi`, `thiserror`, `futures`, and `tokio` using [cargo-edit]:

```sh
cargo add kube --features=runtime,client,derive
cargo add k8s-openapi --features=v1_23
cargo add thiserror
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
thiserror = "LATESTTHISERROR"
```
-->

This will populate some [`[dependencies]`](https://doc.rust-lang.org/cargo/reference/specifying-dependencies.html) in your `Cargo.toml` file.

### Main Dependencies

The [kube] dependency is what we provide. It's used here with its controller `runtime` feature, its Kubernetes `client` and the `derive` macro for custom resources.

The [k8s-openapi] dependency is needed if using core Kubernetes resources.

The [thiserror] dependency is used in this guide as an easy way to do basic error handling, but it is optional.

The [futures] dependency provides helpful abstractions when working with asynchronous rust.

The [tokio] runtime dependency is needed to use async rust features, and is the supported way to use futures created by kube.

!!! warning "Alternate async runtimes"

    We depend on `tokio` for its `time`, `signal` and `sync` features, and while it is in theory possible to swap out a runtime, you would be sacrificing the most actively supported and most advanced runtime available. Avoid going down this alternate path unless you have a good reason.

Additional dependencies are useful, but we will go through these later as we add more features.

### Setting up errors

We will start with the right thing from the start and define a proper `Error` enum:

```rust
#[derive(thiserror::Error, Debug)]
pub enum Error {}

pub type Result<T, E = Error> = std::result::Result<T, E>;
```

### Define the object

Import the [[object]] that you want to control into your `main.rs`.

For the purposes of this demo we are going to use [Pod] (hence the explicit `k8s-openapi` dependency):

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
        .run(reconcile, error_policy, Context::new(()))
        .for_each(|_| futures::future::ready(()))
        .await;

    Ok(())
}
```

This creates a [Client], a Pod [Api] object (for all namespaces), and a [Controller] for the full list of pods defined by a default [ListParams].

We are not using [[relations]] here, so we merely tell the controller to call reconcile when a pod changes.

### Creating the reconciler

You need to define at least a basic `reconcile` fn

```rust
async fn reconcile(obj: Arc<Pod>, ctx: Context<()>) -> Result<Action> {
    println!("reconcile request: {}", obj.name());
    Ok(Action::requeue(Duration::from_secs(3600)))
}
```

and a basic error handler (for what to do when `reconcile` returns an `Err`):

```rust
fn error_policy(_error: &Error, _ctx: Context<()>) -> Action {
    Action::requeue(Duration::from_secs(5))
}
```

To make this reconciler useful, we can reuse the one created in the [[reconciler]] document, on a custom [[object]].

## Checkpoint

If you copy-pasted everything above, and fixed imports, you should have a `src/main.rs` in your `ctrl` directory with this:

```rust
use std::{sync::Arc, time::Duration};
use futures::StreamExt;
use k8s_openapi::api::core::v1::Pod;
use kube::{
    Api, Client, ResourceExt,
    runtime::controller::{Action, Controller, Context}
};

#[derive(thiserror::Error, Debug)]
pub enum Error {}
pub type Result<T, E = Error> = std::result::Result<T, E>;

#[tokio::main]
async fn main() -> Result<(), kube::Error> {
    let client = Client::try_default().await?;
    let pods = Api::<Pod>::all(client);

    Controller::new(pods.clone(), Default::default())
        .run(reconcile, error_policy, Context::new(()))
        .for_each(|_| futures::future::ready(()))
        .await;

    Ok(())
}

async fn reconcile(obj: Arc<Pod>, ctx: Context<()>) -> Result<Action> {
    println!("reconcile request: {}", obj.name());
    Ok(Action::requeue(Duration::from_secs(3600)))
}

fn error_policy(_error: &Error, _ctx: Context<()>) -> Action {
    Action::requeue(Duration::from_secs(5))
}
```

## Developing

At this point, you are ready start the app and see if it works. I.e. you need Kubernetes.

### Prerequisites

> If you already have a cluster, skip this part.

We will develop locally against a `k3d` cluster (which requires `docker` and `kubectl`).

Install the [latest k3d release](https://k3d.io/#releases), then run:

```sh
k3d cluster create kube --servers 1 --agents 1 --registry-create kube
```

If you can run `kubectl get nodes` after this, you are good to go. See [k3d/quick-start](https://k3d.io/#quick-start) for help.

### Local Development

In your `ctrl` directory, you can now `cargo run` and check that you can successfully connect to your cluster.

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

I.e. you should get a reconcile request for every pod in your cluster (`kubectl get pods --all`).

If you now edit a pod (via `kubectl edit pod traefik-xxx` and make a change), or create a new pod, you should immediately get a reconcile request.

**Congratulations**. You have just built your first kube controller. 🎉

!!! note "Continuation"

    At this point, you have gotten the 3 main components; an [[object]], a [[reconciler]] and an [[application]], but there are many topics we have not touched on. Follow the links to other pages to learn more.

## Deploying

### Containerising

WIP. Showcase both multi-stage rust build and musl builds into distroless.

### Containerised Development

WIP. Showcase a basic `tilt` setup with `k3d`.

### Continuous Integration

WIP. In separate document showcase a caching CI setup, and best practice builds; clippy/rustfmt/deny/audit.

## Extras

TODO: link completed WIP documents here.

### Adding observability

Want to add **tracing**, **metrics** or just get better logs than `println`, see the [[observability]] document.

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

These in turn also pull in their own dependencies (and tls features, depending on your tls stack), consult [cargo-tree] for help minimizing your dependency tree.


--8<-- "includes/abbreviations.md"
--8<-- "includes/links.md"

[//begin]: # "Autogenerated link references for markdown compatibility"
[reconciler]: reconciler "The Reconciler"
[object]: object "The Object"
[relations]: relations "Related Objects"
[observability]: observability "Observability"
[//end]: # "Autogenerated link references"
