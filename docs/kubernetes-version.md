
## Policy

Our Kubernetes version compatibility is following a similar strategy to the one employed by [client-go](https://github.com/kubernetes/client-go#compatibility-matrix) and can interoperate under a wide range of Kubernetes versions. We define by a **soft minimum** (MK8SV) based on the current **latest** available Kubernetes version in the _generated source_.

!!! note "Minimum Kubernetes Version Policy"

    The Minimum Supported Kubernetes Version (MK8SV) is **5 releases less than** the **latest** Kubernetes version.

The **minimum** indicates the lower bound of our testing range, and the **latest** is the maximum Kubernetes version selectable as a target version. The minimum has evolved like this:

| kube version   | MK8SV   | Latest  | Generated Source  |
| -------------- | ------- | ------- | ----------------- |
| [0.88.0](https://github.com/kube-rs/kube/releases/tag/0.88.0)  |  `1.24` | [`1.29`](https://kubernetes.io/blog/2023/12/13/kubernetes-v1-29-release/) | [k8s-openapi@0.21.0](https://github.com/Arnavion/k8s-openapi/releases/tag/v0.21.0) |
| [0.86.0](https://github.com/kube-rs/kube/releases/tag/0.86.0)  |  `1.23` | [`1.28`](https://kubernetes.io/blog/2023/08/15/kubernetes-v1-28-release/) | [k8s-openapi@0.20.0](https://github.com/Arnavion/k8s-openapi/releases/tag/v0.20.0) |
| [0.85.0](https://github.com/kube-rs/kube/releases/tag/0.85.0)  |  `1.22` | [`1.27`](https://kubernetes.io/blog/2023/04/11/kubernetes-v1-27-release/) | [k8s-openapi@0.19.0](https://github.com/Arnavion/k8s-openapi/releases/tag/v0.19.0) |
| [0.78.0](https://github.com/kube-rs/kube/releases/tag/0.78.0)  |  `1.21` | [`1.26`](https://kubernetes.io/blog/2022/12/09/kubernetes-v1-26-release/) | [k8s-openapi@0.17.0](https://github.com/Arnavion/k8s-openapi/releases/tag/v0.17.0) |
| [0.75.0](https://github.com/kube-rs/kube/releases/tag/0.75.0)  |  `1.20` | [`1.25`](https://kubernetes.io/blog/2022/08/23/kubernetes-v1-25-release/) | [k8s-openapi@0.16.0](https://github.com/Arnavion/k8s-openapi/releases/tag/v0.16.0) |
| [0.73.0](https://github.com/kube-rs/kube/releases/tag/0.73.0)  |  `1.19` | [`1.24`](https://kubernetes.io/blog/2022/05/03/kubernetes-1-24-release-announcement/) | [k8s-openapi@0.15.0](https://github.com/Arnavion/k8s-openapi/releases/tag/v0.15.0) |
| [0.67.0](https://github.com/kube-rs/kube/releases/tag/0.67.0)  |  `1.18` | [`1.23`](https://kubernetes.io/blog/2021/12/07/kubernetes-1-23-release-announcement/) | [k8s-openapi@0.14.0](https://github.com/Arnavion/k8s-openapi/releases/tag/v0.14.0) |

<!-- NB: k8s-openapi 0.18 did not introduce a new Kubernetes version: https://github.com/Arnavion/k8s-openapi/releases/tag/v0.18.0 so its bump is not listed -->


This policy is intended to match **stable channel support** within **major cloud providers**.
Compare with: [EKS](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html), [AKS](https://docs.microsoft.com/en-us/azure/aks/supported-kubernetes-versions?tabs=azure-cli#aks-kubernetes-release-calendar), [GKE](https://cloud.google.com/kubernetes-engine/docs/release-schedule), [upstream Kubernetes](https://endoflife.date/kubernetes).


It is displayed in the main README as a badge: [![Tested against Kubernetes 1.24 and above](https://img.shields.io/badge/MK8SV-1.24-326ce5.svg)](https://kube.rs/kubernetes-version)

## Picking Versions

Given a `kube` version, you may choose a **target Kubernetes version** from the [available features in the generated source](https://docs.rs/crate/k8s-openapi/latest/features) that is used by that kube version.

### Example

When using [`kube@0.86.0`](https://github.com/kube-rs/kube/releases/tag/0.86.0), the generated source is [`k8s-openapi@0.20.0`](https://github.com/Arnavion/k8s-openapi/releases/tag/v0.20.0), which exports the [following version features](https://docs.rs/crate/k8s-openapi/0.20.0/features). The `latest` supported version feature is _here_ aliased to `v1_28`, our minimum tested version is `v1_23`.

### Guideline

!!! note "Recommendation is `latest`"

    The `latest` feature as your target version is a good default choice, even when running against older clusters.
    Consider **pinning** to a specific cluster version **if** you are programming explicitly against deprecated or alpha apis.

See the [version skew outcomes](#version-skew) if you are unsure whether you need to pin a version.

<!--
With [k8s-pb], we plan on [doing this automatically](https://github.com/kube-rs/k8s-pb/issues/10).
-->

## Version Skew

How kube version skew interacts with clusters is largely determined by how [Kubernetes deprecates api versions upstream](https://kubernetes.io/docs/reference/using-api/deprecation-policy/).

Consider the following outcomes when picking **target versions** based on your **cluster version**:

1. if `target version == cluster version` (cluster in sync with kube), then:
    * kube has api parity with cluster
    * Rust structs are all queryable via kube
2. if `target version > cluster version` (cluster behind kube), then:
    * kube has more recent api features than the cluster supports
    * recent Rust api structs might not work with the cluster version yet
    * deprecated/alpha apis might have been removed from Rust structs ⚡
3. if `target version < cluster version` (cluster ahead of kube), then:
    * kube has less recent api features than the cluster supports
    * recent Kubernetes resources might not have Rust struct counterparts
    * deprecated/alpha apis might have been removed from the cluster ⚡

[Kubernetes takes a long time to remove deprecated apis](https://kubernetes.io/docs/reference/using-api/deprecation-policy/) (unless they alpha or beta apis), so the **acceptable distance** from your **cluster** version **depends** on what **apis you target**.

In particular, when using **stable** (or your own **custom**) api resources, exceeding the range will have little impact.

**If** you are **targeting deprecated/alpha** apis on the other hand, then you should **pick** a target version **in sync with your cluster**, as alpha apis may vanish or change significantly in a single release, and is not covered by any guarantees.

Relying on alpha apis will make the amount of **upgrades required** to an application **more frequent**. To alleviate this; consider using api [discovery] to **match on available api versions** rather than writing code against each Kubernetes version.

## Outside The Range

We recommend developers stay within the supported version range for the best experience, but it is **technically possible** to operate outside the bounds of this range (by picking older features from `k8s-openapi`, or by running against older clusters).

!!! warning "Untested Version Combinations"

    While exceeding the supported version range is likely to work for most api resources: **we do not test** kube's functionality **outside this version range**.

In minor skews, kube and Kubernetes will share a large functioning API surface, while relying on deprecated apis to fill the gap. However, the **further you stray** from the range you are more likely to encounter Rust structs that doesn't work against your cluster, or miss support for resources entirely.

## Abstractions

For a small number of api resources, kube provides abstractions that are not managed along with the generated sources. For these cases we __track the source__ and remove when Kubernetes removes them (to avoid double dipping on deprecation time).

This affects a small number of special resources such as `CustomResourceDefinition`, `Event`, `Lease`, `AdmissionReview`.

### Example

The `CustomResourceDefinition` resource at `v1beta1` was [removed](https://kubernetes.io/docs/reference/using-api/deprecation-guide/) in Kubernetes `1.22`:

> The apiextensions.k8s.io/v1beta1 API version of CustomResourceDefinition is no longer served as of v1.22.

Their replacement; in `v1` was released in Kubernetes `1.16`.

Kube had special support for both versions of `CustomResourceDefinition` from `0.26.0` up until [`0.72.0`](https://github.com/kube-rs/kube/releases/tag/0.72.0) when kube supported structs from Kubernetes >= 1.22.

This special support took the form of the proc macro [CustomResource] and [associated helpers](https://docs.rs/kube/latest/kube/core/crd/index.html) that allowing pinning the crd version to `v1beta1` up until its removal. It is now `v1` only.

--8<-- "includes/abbreviations.md"
--8<-- "includes/links.md"
