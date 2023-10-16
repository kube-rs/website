# The Object

A controller always needs a __source of truth__ for **what the world should look like**, and this object **always lives inside kubernetes**.

Depending on how the object was created/imported or performance optimization reasons, you can pick one of the following object archetypes:

- typed Kubernetes native resource
- Derived Custom Resource for Kubernetes
- Imported Custom Resource already in Kubernetes
- untyped Kubernetes resource
- partially typed Kubernetes resource

We will outline how they interact with controllers and the basics of how to set them up.

## Typed Resource

This is the most common, and simplest case. Your source of truth is an existing [Kubernetes object found in the openapi spec](https://arnavion.github.io/k8s-openapi/v0.14.x/k8s_openapi/trait.Resource.html#implementors).

To use a typed Kubernetes resource as a source of truth in a [Controller], import it from [k8s-openapi], and create an [Api] from it, then pass it to the [Controller].

```rust
use k8s_openapi::api::core::v1::Pod;

let pods = Api::<Pod>::all(client);
Controller::new(pods, watcher::Config::default())
```

This is the simplest flow and works right out of the box because the openapi implementation ensures we have all the api information via the [Resource] traits.

If you have a native Kubernetes type, **you generally want to start with [k8s-openapi]**. If will likely do exactly what you want without further issues. **That said**, if both your clusters and your chosen object are large, then you can **consider optimizing** further by changing to a [partially typed resource](#partially-typed-resource) for smaller memory profile.

A separate [k8s-pb] repository for our [future protobuf serialization structs](https://github.com/kube-rs/kube/issues/725) also exists, and while it will slot into this category and should hotswappable with [k8s-openapi], it is **not yet usable** here.

## Custom Resources
### Derived Custom Resource

The operator use case is heavily based on you writing your own struct, and a schema, and [extending the kuberntes api](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/) with it.

This **has** historically required a lot of boilerplate for both the api information and the (now required) [schema](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/#validation-rules), but this is a lot simpler with kube thanks to the [CustomResource] derive [proc_macro].

```rust
/// Our Document custom resource spec
#[derive(CustomResource, Deserialize, Serialize, Clone, Debug, JsonSchema)]
#[kube(kind = "Document", group = "kube.rs", version = "v1", namespaced)]
#[kube(status = "DocumentStatus")]
pub struct DocumentSpec {
    name: String,
    author: String,
}

#[derive(Deserialize, Serialize, Clone, Debug, JsonSchema)]
pub struct DocumentStatus {
    checksum: String,
    last_updated: Option<DateTime<Utc>>,
}
```

This will generate a `pub struct Document` in this scope which implements [Resource]. In other words, to use it with the a controller is at this point analogous to a fully typed resource:

```rs
let docs = Api::<Document>::all(client);
Controller::new(docs, watcher::Config::default())
```

!!! note "Custom resources require schemas"

    Kubernetes requires openapi schemas inside every [CustomResourceDefinition] ([since Kubernetes 1.22](https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG/CHANGELOG-1.22.md#removal-of-several-beta-kubernetes-apis)). Below we use the standard mechanism of deriving `JsonSchema` using [schemars]. See [[schemas]] for details.

#### Installation

Before Kubernetes accepts api calls for a custom resource, we need to install it. This is the usual pattern for creating the yaml definition:

```toml
# Cargo.toml
[[bin]]
name = "crdgen"
path = "src/crdgen.rs"
```

```rust
// crdgen.rs
use kube::CustomResourceExt;
fn main() {
    print!("{}", serde_yaml::to_string(&mylib::Document::crd()).unwrap())
}
```

Here, a separate `crdgen` bin entry would install your custom resource using `cargo run --bin crdgen | kubectl -f -`.

!!! warning "CRD Installation"

    Be careful with installing CRDs inside a controller at starup. It is customary to provide a generated yaml file so consumers can install a CRD out of band to better support [gitops](https://fluxcd.io/flux/components/helm/helmreleases/#crds) and [helm](https://helm.sh/docs/chart_best_practices/custom_resource_definitions/). See [[security#crd-access]].

### Imported Custom Resource

In the case that a `customresourcedefinition` **already exists**, but it was **implemented in another language**, then we can **generate structs from the schema** using [kopium].

Suppose you want to write some extra controller or replace the native controller for `PrometheusRule`:

```sh
curl -sSL https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd/monitoring.coreos.com_prometheusrules.yaml \
    | kopium -Af - > prometheusrule.rs
```

this will read the crd from a file / cluster, and generate rust-optimized structs for it:

```rust
use kube::CustomResource;
use schemars::JsonSchema;
use serde::{Serialize, Deserialize};
use std::collections::BTreeMap;
use k8s_openapi::apimachinery::pkg::util::intstr::IntOrString;

/// Specification of desired alerting rule definitions for Prometheus.
#[derive(CustomResource, Serialize, Deserialize, Clone, Debug, JsonSchema)]
#[kube(group = "monitoring.coreos.com", version = "v1", kind = "PrometheusRule", plural = "prometheusrules")]
#[kube(namespaced)]
pub struct PrometheusRuleSpec {
    /// Content of Prometheus rule file
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub groups: Option<Vec<PrometheusRuleGroups>>,
}

/// RuleGroup is a list of sequentially evaluated recording and alerting rules.
#[derive(Serialize, Deserialize, Clone, Debug, JsonSchema)]
pub struct PrometheusRuleGroups {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub interval: Option<String>,
    pub name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub partial_response_strategy: Option<String>,
    pub rules: Vec<PrometheusRuleGroupsRules>,
}

/// Rule describes an alerting or recording rule
#[derive(Serialize, Deserialize, Clone, Debug, JsonSchema)]
pub struct PrometheusRuleGroupsRules {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub alert: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub annotations: Option<BTreeMap<String, String>>,
    pub expr: IntOrString,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub r#for: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub labels: Option<BTreeMap<String, String>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub record: Option<String>,
}
```

you typically would then import this file as a module and use it as follows:

```rust
use prometheusrule::PrometheusRule;

let prs: Api<PrometheusRule> = Api::default_namespaced(client);
Controller::new(prs, watcher::Config::default())
```

!!! warning "Kopium is unstable"

    Kopium is a relatively new project and it is [neither feature complete nor bug free at the moment](https://github.com/kube-rs/kopium/issues). While feedback has been very positive, and people have so far contributed fixes for several major customresources; **expect some snags**.
## Dynamic Typing


### Untyped Resources

Untyped resources are using [DynamicObject]; an umbrella container for arbitrary Kubernetes resources.

!!! warning "Hard to use with controllers"

    This type is the most unergonomic variant available. You will have to operate on [untyped json](https://docs.serde.rs/serde_json/#operating-on-untyped-json-values) to grab data out of specifications and is best suited for general (non-controller) cases where you need to look at common metadata properties from [ObjectMeta] like `labels` and `annotations` across different object types.

The [DynamicObject] consists of **just the unavoidable properties** like `apiVersion`, `kind`, and `metadata`, whereas the entire spec is loaded onto an arbitrary [serde_json::Value] via [flattening].

The benefits you get is that:

- you avoid having to write out fields manually
- you **can** achieve tolerance against multiple versions of your object
- it is compatible with api [discovery]

but you do have to find out where the object lives on the api (its [ApiResource]) manually:

```rust
use kube::{api::{Api, DynamicObject}, discovery};

// Discover most stable version variant of `documents.kube.rs`
let apigroup = discovery::group(&client, "kube.rs").await?;
let (ar, caps) = apigroup.recommended_kind("Document").unwrap();

// Use the discovered kind in an Api, and Controller with the ApiResource as its DynamicType
let api: Api<DynamicObject> = Api::all_with(client, &ar);
Controller::new_with(api, watcher::Config::default(), &ar)
```

Other ways of doing [discovery] are also available. We are highlighting [recommended_kind] in particular here because it can be used to achieve version agnosticity.

!!! note "Multiple versions of an object"

    Kubernetes supports specifying [multiple versions of a specification](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definition-versioning/), and using [DynamicObject] above can help solve that. There are [other potential ways](https://github.com/kube-rs/kube/issues/569) of achieving similar results, but it does require some work.

### Partially-typed Resource

You can __partially implement structs__ for an existing resource. This can be to manually control memory characteristic, deserialization parameters, or api parameters. It is done by using [Object] on an incomplete struct and supplying an existing [ApiResource].

This can be a quick way to control memory use, or to shield your app against the full api surface or versions of a quickly moving CRD.

!!! note "Memory Optimizations"

    An easier way to control memory use of stores is via [[optimization#Pruning Fields]].

As an **example**; a handwritten implementation of [Pod] by overriding its **spec** and **status** and placing it inside [Object], then **stealing** its type information from `k8s-openapi`:

```rust
use kube::api::{Api, ApiResource, NotUsed, Object};

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
// Pod replacement
type PodSimple = Object<PodSpecSimple, NotUsed>;

// steal api resource information from k8s-openapi
let ar = ApiResource::erase::<k8s_openapi::api::core::v1::Pod>(&());

Controller::new_with(api, watcher::Config::default(), &ar)
```

We have to recursively re-implement every part of [Pod] that we care about, but we automatically drop every field except the ones we defined. In this case we do not gain version independence (due to re-using pinned type-information), but you could gain this by using api [discovery].

This is functionally similar way to deriving `CustomResource` on an incomplete struct, but using (possibly) dynamic api parameters.

### Dynamic new_with constructors

!!! warning "Partial or dynamic typing always needs additional type information"

    All usage of `DynamicObject` or `Object` require the use of alternate constructors for multiple interfaces such as [Api] and [Controller]. These constructors have an additional `_with` suffix to carry an associated type for the [Resource] trait.

## Summary

All the fully typed methods all have a **consistent usage pattern** once the types have been generated. The dynamic and partial objects have more niche use cases and require a little more work such as alternate constructors.

| typing                    | Source                               | Implementation              |
| ------------------------- | ------------------------------------ |---------------------------- |
| :material-check-all: full | [k8s-openapi]                        | `use k8s-openapi::X`        |
| :material-check-all: full | kube::[CustomResource]               | `#[derive(CustomResource)]` |
| :material-check-all: full | [kopium]                             | `kopium crd > gen.rs`       |
| :material-check: partial  | kube::core::[Object]                 | partial handwrite           |
| :material-close: none     | kube::core::[DynamicObject]          | fully dynamic               |

--8<-- "includes/abbreviations.md"
--8<-- "includes/links.md"
