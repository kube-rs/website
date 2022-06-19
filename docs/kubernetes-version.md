## Compatibility

Our Kubernetes version compatibility is similar to the strategy employed by [client-go](https://github.com/kubernetes/client-go#compatibility-matrix) and can interoperate well under a wide range of target Kubernetes versions defined by a **soft minimum** (MK8SV) and  the current **latest** available Kubernetes feature version.

| kube version   | MK8SV   | Latest  | Generated Source  |
| -------------- | ------- | ------- | ----------------- |
| `0.48.0`       |  `1.15` | [`1.20`](https://kubernetes.io/blog/2020/12/08/kubernetes-1-20-release-announcement/) | [k8s-openapi@0.11.0](https://github.com/Arnavion/k8s-openapi/blob/master/CHANGELOG.md#v0110-2021-01-23) |
| `0.57.0`       |  `1.16` | [`1.21`](https://kubernetes.io/blog/2021/04/08/kubernetes-1-21-release-announcement/) | [k8s-openapi@0.12.0](https://github.com/Arnavion/k8s-openapi/blob/master/CHANGELOG.md#v0120-2021-06-15) |
| `0.66.0`       |  `1.17` | [`1.22`](https://kubernetes.io/blog/2021/08/04/kubernetes-1-22-release-announcement/) | [k8s-openapi@0.13.0](https://github.com/Arnavion/k8s-openapi/blob/master/CHANGELOG.md#v0131-2021-10-08) |
| `0.67.0`       |  `1.18` | [`1.23`](https://kubernetes.io/blog/2021/12/07/kubernetes-1-23-release-announcement/) | [k8s-openapi@0.14.0](https://github.com/Arnavion/k8s-openapi/blob/master/CHANGELOG.md#v0140-2022-01-23) |
| `0.73.0`       |  `1.19` | [`1.24`](https://kubernetes.io/blog/2022/05/03/kubernetes-1-24-release-announcement/) | [k8s-openapi@0.15.0](https://github.com/Arnavion/k8s-openapi/blob/master/CHANGELOG.md#v0150-2022-05-22) |

The MK8SV is listed in our README as a badge:

> [![Tested against Kubernetes 1.19 and above](https://img.shields.io/badge/MK8SV-1.19-326ce5.svg)](https://kube.rs/kubernetes-version)

The **minimum** indicates the lower bound of our testing range, and the **latest** is the Kubernetes version selectable as a target version, indicating how much of the latest api surface we support.

!!! note "Minimum Kubernetes Version Policy"

    The Minimum Supported Kubernetes Version (MK8SV) is set as **5 releases below** the **latest** Kubernetes version.

This policy is intended to match **stable channel support** within **major cloud providers**.
Compare with: [EKS](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html), [AKS](https://docs.microsoft.com/en-us/azure/aks/supported-kubernetes-versions?tabs=azure-cli#aks-kubernetes-release-calendar), [GKE](https://cloud.google.com/kubernetes-engine/docs/release-notes-stable), [upstream Kubernetes](https://endoflife.date/google-kubernetes-engine).

## Picking Versions

Given a `kube` versions, you must pick a **target Kubernetes version** from the available ones in the generated source that is used by that kube version.

E.g. if using [`kube@0.73.0`](https://docs.rs/kube/0.73.0/kube/), we see its generated source is [`k8s-openapi@0.15.0`](https://docs.rs/k8s-openapi/0.15.0/k8s_openapi/), which exports the [following version features](https://docs.rs/crate/k8s-openapi/0.15.0/features).

You can find the latest supported from this feature list and pick this as your target. In this case the latest supported version feature is `v1_24`.

By default; you **SHOULD** pick the latest as your target version even when running against older clusters. The **exception** is if you are programming explicitly against apis that have been removed in newer versions.

With [k8s-pb], we plan on [doing this automatically](https://github.com/kube-rs/k8s-pb/issues/10).

See below for details on a skew between your cluster and your target version.

## Version Skew

How kube version skew interacts with clusters is largely determined by how [Kubernetes deprecates api versions upstream](https://kubernetes.io/docs/reference/using-api/deprecation-policy/).

Consider the following outcomes when picking **target versions** based on your **cluster version**:

1. if `target version == cluster version` (cluster in sync with kube), then:
    * kube has api parity with cluster
    * Rust structs are all queryable via kube
2. if `target version > cluster version` (cluster behind kube), then:
    * kube has more recent api features than the cluster supports
    * recent Rust api structs might not work with the cluster version yet
    * [deprecated](https://kubernetes.io/docs/reference/using-api/deprecation-policy/)/alpha apis might have been removed from Rust structs ⚡
3. if `target version < cluster version` (cluster ahead of kube), then:
    * kube has less recent api features than the cluster supports
    * recent Kubernetes resources might not have Rust struct counterparts
    * [deprecated](https://kubernetes.io/docs/reference/using-api/deprecation-policy/)/alpha apis might have been removed from the cluster ⚡

Kubernetes takes a long time to remove deprecated apis (unless they alpha or beta apis), so the **acceptable distance** from your **cluster** version actually **depends** on what **apis you target**.

In particular, when using your own **custom** or **stable official** api resources - where exceeding the range will have **little impact**.

**If** you are **targeting deprecated/alpha** apis on the other hand, then you should **pick** a target version **in sync with your cluster**. Note that alpha apis may vanish or change significantly in a single release, and is not covered by any guarantees.

As a result; relying on alpha apis will make the amount of **upgrades required** to an application **more frequent**. To alleviate this; consider using api [discovery] to **match on available api versions** rather than writing code against each Kubernetes version.

## Outside The Range

We recommend developers stay within the supported version range for the best experience, but it is **technically possible** to operate outside the bounds of this range (by picking older `k8s-openapi` features, or by running against older clusters).

!!! warning "Untested Version Combinations"

    While exceeding the supported version range is likely to work for most api resources: **we do not test** kube's functionality **outside this version range**.

In minor skews, both kube and Kubernetes will share a large functioning API surface, while relying on deprecated apis to fill the gap. However, the **further you stray** from the range you are **increasingly likely** to encounter Rust structs that doesn't work against your cluster, or miss support for resources entirely.

## Special Abstractions

In a small number of cases, kube provides abstractions on top of certain api resources that are not managed along with the generated sources. For these cases we currently __track the source__ and remove when Kubernetes removes them.

This only affects a small number of special resources such as `CustomResourceDefinition`, `Event`, `Lease`, `AdmissionReview`.

### Example

The `CustomResourceDefinition` resource at `v1beta1` was [removed](https://kubernetes.io/docs/reference/using-api/deprecation-guide/) in Kubernetes `1.22`:

> The apiextensions.k8s.io/v1beta1 API version of CustomResourceDefinition is no longer served as of v1.22.

Their replacement; in `v1` was released in Kubernetes `1.16`.

Kube had special support for both versions of `CustomResourceDefinition` from `0.26.0` up until [`0.72.0`](https://github.com/kube-rs/kube-rs/releases/tag/0.72.0) when kube supported structs from Kubernetes >= 1.22.

This special support took the form of the proc macro [CustomResource] and [associated helpers](https://docs.rs/kube/latest/kube/core/crd/index.html) that allowing pinning the crd version to `v1beta1` up until its removal. It is now `v1` only.

--8<-- "includes/abbreviations.md"
--8<-- "includes/links.md"
