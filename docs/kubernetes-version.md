## Compatibility

Our Kubernetes version compatibility is similar to the strategy employed by [client-go](https://github.com/kubernetes/client-go#compatibility-matrix) and can interoperate well under a wide range of target Kubernetes versions defined by a **soft minimum** (MINK8SV) and a **soft maximum** (MAXK8SV):

| kube version   | MINK8SV   | MAXK8SV  | Generated Source  |
| -------------- | --------- | -------- | ----------------- |
| `0.48.0`       |  `1.16`   | `1.20`   | [k8s-openapi@0.11.0](https://github.com/Arnavion/k8s-openapi/blob/master/CHANGELOG.md#v0110-2021-01-23) |
| `0.57.0`       |  `1.17`   | `1.21`   | [k8s-openapi@0.12.0](https://github.com/Arnavion/k8s-openapi/blob/master/CHANGELOG.md#v0120-2021-06-15) |
| `0.66.0`       |  `1.18`   | `1.22`   | [k8s-openapi@0.13.0](https://github.com/Arnavion/k8s-openapi/blob/master/CHANGELOG.md#v0131-2021-10-08) |
| `0.67.0`       |  `1.19`   | `1.23`   | [k8s-openapi@0.14.0](https://github.com/Arnavion/k8s-openapi/blob/master/CHANGELOG.md#v0140-2022-01-23) |
| `0.73.0`       |  `1.20`   | `1.24`   | [k8s-openapi@0.15.0](https://github.com/Arnavion/k8s-openapi/blob/master/CHANGELOG.md#v0150-2022-05-22) |


 The **maximum** indicates how much of the latest api surface we support, and can be in general be exceeded. The **minimum** indicates the lower bound of our testing range (4 versions from the maximu - matching [Kubernetes support range](https://endoflife.date/kubernetes).

 The MAXK8SV is shown as a readme badge:

 > [![Kubernetes 1.24](https://img.shields.io/badge/K8s-1.24-326ce5.svg)](https://kube.rs/kubernetes-version)
## Picking Versions

Given a `kube` versions, you must pick a **target Kubernetes version** from the available ones in the generated source that is used by that kube version.

E.g. if using [`kube@0.73.0`](https://docs.rs/kube/0.73.0/kube/), we see its generated source is [`k8s-openapi@0.15.0`](https://docs.rs/k8s-openapi/0.15.0/k8s_openapi/), which exports the [following version features](https://docs.rs/crate/k8s-openapi/0.15.0/features).

You can find the MAXK8SV from this feature list and pick this as your target. In this case the maximally supported version feature is `v1_24`.

By default; you **SHOULD** pick the MAXK8SV as your target version even when running against older clusters. The **exception** is if you are programming explicitly against apis that have been removed in newer versions.

With [k8s-pb], we plan on [doing this automatically](https://github.com/kube-rs/k8s-pb/issues/10).

See below for details on a skew between your cluster and your target version.

## Version Skew

How kube version skew interacts with clusters is largely determined by how [Kubernetes deprecates api versions upstream](https://kubernetes.io/docs/reference/using-api/deprecation-policy/).

Consider the following outcomes when picking **target versions** based on your **cluster version**:

1. if `target version == cluster version` (cluster in sync with kube), then:
    * kube has api parity with cluster
    * rust structs are all queryable via kube
2. if `target version > cluster version` (cluster behind kube), then:
    * kube has more recent api features than the cluster supports
    * recent rust api structs might not work with the cluster version yet
    * [deprecated](https://kubernetes.io/docs/reference/using-api/deprecation-policy/)/alpha apis might have been removed from rust structs ⚡
3. if `target version < cluster version` (cluster ahead of kube), then:
    * kube has less recent api features than the cluster supports
    * recent kubernetes resources might not have rust struct counterparts
    * [deprecated](https://kubernetes.io/docs/reference/using-api/deprecation-policy/)/alpha apis might have been removed from the cluster ⚡

Kubernetes takes a long time to remove deprecated apis (unless they alpha or beta apis), so the **acceptable distance** from your **cluster** version actually **depends** on what **apis you target**.

In particular, when using your own **custom** or **stable official** api resources - where exceeding the range will have **little impact**.

**If** you are **targeting deprecated/alpha** apis on the other hand, then you should **pick** a target version **in sync with your cluster**. Note that alpha apis may vanish or change significantly in a single release, and is not covered by any guarantees.

As a result; relying on alpha apis will make the amount of **upgrades required** to an application **more frequent**. To alleviate this; consider using api [discovery] to **match on available api versions** rather than writing code against each Kubernetes version.

## Exceeding The Range

We recommend developers stay within the supported version range for the best experience, but it is **technically possible** to operate outside the bounds of this range (by picking older `k8s-openapi` features, or by running against older clusters).

!!! warning "Untested Version Combinations"

    While exceeding the supported version range **can** work: **we do not test** kube's functionality **outside this version range**.

In minor skews, both kube and Kubernetes will share a large functioning API surface, while relying on deprecated apis to fill the gap. However, the **further you stray** from the range you are **increasingly likely** to encounter rust structs that doesn't work against your cluster, or miss support for resources entirely.


--8<-- "includes/abbreviations.md"
--8<-- "includes/links.md"
