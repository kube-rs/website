# Stability
[![Client Support Level; Stable](https://img.shields.io/badge/kubernetes%20client-stable-green.svg?style=plastic&colorA=306CE8)](https://github.com/kubernetes/design-proposals-archive/blob/main/api-machinery/csi-new-client-library-procedure.md#client-support-level)

`kube` satisfies the [client level requirements for a Stable Client](https://github.com/kubernetes/design-proposals-archive/blob/main/api-machinery/csi-new-client-library-procedure.md#client-support-level).

## Platform Support Level

Our support level is determined by our continuous integration.

[Github Actions](https://github.com/kube-rs/kube/actions/workflows/ci.yml) continually builds and tests `kube` against the [LTS supported environments](https://github.com/actions/virtual-environments#available-environments) for **Ubuntu**, and **macOS**, and **Windows**:

| Support                        | Source         | Guarantee        | Upstream Policy |
| ------------------------------ | -------------- | ---------------- | ---------- |
| :material-check-all: supported | Linux          | `ubuntu-latest`  | [2 years](https://ubuntu.com/about/release-cycle)    |
| :material-check-all: supported | Windows        | `windows-latest` | [3 years](https://docs.microsoft.com/en-us/windows-server/get-started/windows-server-release-info)    |
| :material-check-all: supported | macOS          | `macos-latest`   | [1 year](https://en.wikipedia.org/wiki/MacOS_version_history#Releases)   |

## Kubernetes Distribution Support

We follow upstream api-conventions and is designed to work for any [Kubernetes conformant distribution](https://www.cncf.io/certification/software-conformance/).

Apart from a single [upstream deprecated](https://cloud.google.com/kubernetes-engine/docs/deprecations/auth-plugin) auth plugin for GCP (that we maintain compatibility for), all `kube` logic is otherwise distribution agnostic.

For version compatibility against `EKS`, `GKE`, `AKS`, you may cross-reference with our [[kubernetes-version]] policy (designed to match their lifecycles).

<!-- TODO: if we get e2e extended to test auth against specific distros,
then also print table of tested Kubernetes distros such as k3s, EKS, GKE, AKS -->

## Interface Changes

Public interfaces from `kube` is allowed to change between **semver breaking** versions, provided github release & [[changelog]] provides adequate guidance on the change, and the amount of user facing changes is minimized and trivialised. In particular:

- PRs that perform breaking changes **must** have the `changelog-change` label
- changes needed to user code **should** have a [diff code comment](https://github.com/kube-rs/kube/releases/tag/0.73.0) on the change
- changes as a result of interface changes **should** be explained
- changes that affect controller-rs or version-rs, **should** link to a fixing commit
- renamed functions/changed arguments/changing imports, **should** show what to search/replace in the PR
- changes to experimental features using [[#unstable-features]] **should** have an `unstable` label

We **prefer [deprecations](#deprecation-strategy) and duplication** of logic where it **avoids confusion**.

## Deprecation Strategy

Altered methods/fns/constants **should** in general not be changed directly, but instead have a new alternative implementation introduced to avoid users receiving confusing compile errors.

New variants **should** have a new name, and the old variant **should** remain with a **deprecation attribute** that can guide users towards the new behaviour before the deprecated variant disappears.

!!! note "Deprecation Duration"

    Deprecated functionality **must** stick around for at least **3 major releases**.

For instance, if we deprecate a method in `1.0.0` (the major released for Kubernetes 1.33), then the deprecated method must still exist in future `1.X` releases as well as `2.X` (the major release for Kubernetes 1.34) and `3.X` (the major release for Kubernetes 1.35). We should only remove this method for a `4.0` release.

Deprecations should use a deprecated attribute with a note of removal. Ala [`runtime::utils::try_flatten_applied`](https://github.com/kube-rs/kube/blob/d0bf02f9c0783a3087b83633f2fa899d8539e91d/kube-runtime/src/utils/mod.rs#L29-L40) which was slated for removal in `0.75.0`.

```rust
/// Flattens each item in the list following the rules of [`watcher::Event::into_iter_applied`].
#[deprecated(
    since = "0.72.0",
    note = "fn replaced with the WatchStreamExt::applied_objects which can be chained onto watcher. Add `use kube::runtime::WatchStreamExt;` and call `stream.applied_objects()` instead. This function will be removed in 0.75.0."
)]
pub fn try_flatten_applied<K, S: TryStream<Ok = watcher::Event<K>>>(
    stream: S,
) -> impl Stream<Item = Result<K, S::Error>> {
    stream
        .map_ok(|event| stream::iter(event.into_iter_applied().map(Ok)))
        .try_flatten()
}
```

Internal usage of this function was removed when it was deprecated, but it is kept in place as a convenience to people upgrading for at least 3 versions.

The deprecation note **must** point out viable alternatives, and **must** point out the scheduled removal version.
## Unstable Features

When adding new, experimental functionality, we export them through optional features that must be explicitly enabled.

These features are **opt-in** using [cargo features](https://doc.rust-lang.org/cargo/reference/features.html), and can be enabled from your `Cargo.toml`:

```toml
kube = { version = "1", features = ["runtime", "unstable-runtime"] }
```

Functionality released under unstable features **can change between any version** and are **not subject** to **any** of the usual **guarantees**.

### Feature Selection vs. Compile Flags
We acknowledge that using features selection for unstable functionality does come with the downside that users can sometime have these features selected for them through intermediary crates that also depend on kube.

Tokio for instance, instead relies on [compile flags](https://docs.rs/tokio/1.26.0/tokio/index.html#unstable-features) due to this possibility, even though it is slightly more awkward for users.

For `kube`, our position is more frequently a direct application dependency rather than as another library building-block. Thus, we feel the possibility of unstable features being accidentally enabled for end-users to be low enough to not warrant the extra hassle of using compile flags.

That said, library publishers that depend on `kube` **should** only publish unstable kube behavior under their own unstable feature sets, or in pre-1.0 crates.

### Feature Exporting
Features are exported by each crate initially;

E.g. from `kube-runtime`:

```toml
kube-runtime/Cargo.toml
18:unstable-runtime = ["unstable-runtime-subscribe"]
19:unstable-runtime-subscribe = []
```

then the major feature is re-exported from `kube`:

```toml
kube/Cargo.toml
31:unstable-runtime = ["kube-runtime/unstable-runtime"]
```

## Major Release Cycle

Our codebase has generally stabilised, we officially satisfy the [upstream requirements for stability](https://github.com/kubernetes/design-proposals-archive/blob/main/api-machinery/csi-new-client-library-procedure.md#client-support-level), and we have started releasing major versions. However, we still have sub-1.0 dependencies. How does this work?

1. Any future minor bump of sub-1.0 dependencies that have a public/peer boundary (such as k8s-openapi, schemars) will coincide with a new `kube` major version.
2. Every 3 months there's a new Kubernetes version resulting in a new semver breaking `k8s-openapi`.

!!! note "Major Release Policy"

    To align breaking changes to a predictable cycle, we aim to ship these semver breaking upgrades for new Kubernetes versions as a major kube version. Additional care to limit any non-mandatory, internal breaking changes still follow our normal guidelines above.

This means that occasionally we are behind on some unstable dependencies, but this should be rectified in the new version. Any relevant required upgrades will be listed in the [version table](https://kube.rs/kubernetes-version/).

We feel this currently best reflects the state of reality; `kube` mirrors a large part of the api surface of Kubernetes, so our major releases should correspond to large changes in Kubernetes.

Currently this means having to do semver breaking releases, but this might not remain true forever.

## Future Features
There are also some features that we have wanted to get properly in place, but they are so far proving elusive. These are

1. [protobuf serialization layer](https://github.com/kube-rs/kube/issues/725) is WIP
   a). This is likely to force new features (possibly making `k8s-openapi` opt-in)
   b). This might require core traits to be moved out of `kube-core`
2. [Client Api Methods](https://github.com/kube-rs/kube/issues/1032) is WIP
   a). This might require some re-work of the dynamic api
   b). This might change how we advertise how users should use our kube-client (though we are unlikely to ever remove `Api`)
3. [`Controller` runtime features for stream sharing](https://github.com/kube-rs/kube/issues/1080) are WIP
   a). This is being tested out through unstable features
   b). Controller signatures might need tweaking to accommodate these

If/when these land, they are likely to live under unstable features for a while, and only properly introduced as breaking changes in major versions.

## Summary
As a brief summary to these policies and constraints, our approach to stability is to:

- **track** our breaking changes with [changelog-change labeled PRs](https://github.com/kube-rs/kube/pulls?q=is%3Apr+label%3Achangelog-change+is%3Aclosed)
- **inform** on necessary changes in [releases](https://github.com/kube-rs/kube/releases) and the [[changelog]]
- **carefully change** according to our [guidelines on interface changes](#interface-changes)
- **experiment** with new functionality under [unstable feature flags](#unstable-features)
- **deprecate** according to our [deprecation strategy](#deprecation-strategy)

<!--
## Panic Policy
TODO: need to address this at some point.
-->

--8<-- "includes/abbreviations.md"
--8<-- "includes/links.md"

[//begin]: # "Autogenerated link references for markdown compatibility"
[kubernetes-version]: kubernetes-version "kubernetes-version"
[changelog]: changelog "Changelog"
[#unstable-features]: stability "Stability"
[//end]: # "Autogenerated link references"
