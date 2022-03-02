# The Object

A controller always needs a __source of truth__ for **what the world should look like**, and this object **always lives inside kubernetes**.

Depending on how the object was created/imported or performance optimization reasons, it can take one of the following forms:

- typed Kubernetes native resources
- dynamically typed Kubernetes resources
- partially typed Kubernetes resources
- Generated Custom Resources for Kubernetes
- Imported Custom Resources already in Kubernetes

## Typed Resources

This is the most common, and simplest case. Your source of truth is an existing [Kubernetes object found in the openapi spec](https://arnavion.github.io/k8s-openapi/v0.14.x/k8s_openapi/trait.Resource.html#implementors).

To use a typed Kubernetes resource as a source of truth in a [Controller], import it from [k8s-openapi], and create an [Api] from it, then pass it to the [Controller].

```rust
use k8s_openapi::api::core::v1::Pod;

let pods = Api::<Pod>::all(client.clone());
Controller::new(pods, ListParams::default());
```

NB: `k8s-pb` is currently not yet supported as a typed resource in `kube-rs`, but will be some day.

## Dynamic Resources

kube-client with discovery -> DynamicObject

```rust
use kube::{
    api::{Api, DynamicObject, GroupVersionKind, ListParams, ResourceExt},
    discovery,
};

let group = "clux.dev".to_string();
let version = "v1".to_string();
let kind = "Foo".to_string();

// Turn them into a GVK
let gvk = GroupVersionKind::gvk(&group, &version, &kind);
// Use API discovery to identify more information about the type (like its plural)
let (ar, _caps) = discovery::pinned_kind(&client, &gvk).await?;

// Use the discovered kind in an Api with the ApiResource as its DynamicType
let api = Api::<DynamicObject>::all_with(client, &ar);
```

This object is basically not typed at all. `DynamicObject` contains a `flattened` (TODO serde link) set of remainder values and must be parsed manually as per the api of `serde_json::Value`.

Using this type of object generally does not make sense for objects that exist inside `k8s-openapi` unless you need to handle arbitrary sets of resources yourself (which within controllers are unlikely).

## Partially-typed Resources

These resources sit somewhere between dynamically typed and fully typed, and is generally written to improve memory characterstics of the program.


```rust
use kube::api::{Api, ApiResource, NotUsed, Object, ResourceExt};

// Here we replace heavy type k8s_openapi::api::core::v1::PodSpec with
#[derive(Clone, Deserialize, Debug)]
struct PodSpecSimple {
    containers: Vec<ContainerSimple>,
}
#[derive(Clone, Deserialize, Debug)]
struct ContainerSimple {
    #[allow(dead_code)]
    image: String,
}
type PodSimple = Object<PodSpecSimple, NotUsed>;
```

Using `Object` immediately implements `kube::Resource` so it can be used inside a controller.

## Generated Custom Resources

kube-derive
## Imported Custom Resources

`kopium` imported types to create further functionality in rust rather than what it was originally written in.


## Summary

| typing                    | Source                               | Implementation              |
| ------------------------- | ------------------------------------ |---------------------------- |
| :material-check-all: full | k8s-openapi                          | `use k8s-openapi::X`        |
| :material-check-all: full | kube_derive::CustomResource          | `#[derive(CustomResource)]` |
| :material-check-all: full | kopium                               | `kopium > gen.rs`           |
| :material-check: partial  | kube::core::Object                   | partial copy-paste          |
| :material-close: dynamic  | kube::core::DynamicObject            | write nothing               |

--8<-- "includes/abbreviations.md"
--8<-- "includes/links.md"
