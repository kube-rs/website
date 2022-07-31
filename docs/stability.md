# Stability

`kube` satisfies the [client level requirements](https://github.com/kubernetes/design-proposals-archive/blob/main/api-machinery/csi-new-client-library-procedure.md#client-support-level) for [![Client Support Level; Stable](https://img.shields.io/badge/kubernetes%20client-stable-green.svg?style=plastic&colorA=306CE8)](https://github.com/kubernetes/design-proposals-archive/blob/main/api-machinery/csi-new-client-library-procedure.md#client-support-level)

## Platform Support Level

Our support level is determined by our continuous integration.

[Github Actions](https://github.com/kube-rs/kube-rs/actions/workflows/ci.yml) continually builds and tests `kube` against the [LTS supported environments](https://github.com/actions/virtual-environments#available-environments) for **Ubuntu**, and **macOS**, and **Windows**:

| Support                        | Source         | Guarantee        | LTS Cycle  |
| ------------------------------ | -------------- | ---------------- | ---------- |
| :material-check-all: supported | Linux          | `ubuntu-latest`  | [2 years](https://ubuntu.com/about/release-cycle)    |
| :material-check-all: supported | Windows        | `windows-latest` | [3 years](https://docs.microsoft.com/en-us/windows-server/get-started/windows-server-release-info)    |
| :material-check-all: supported | macOS          | `macos-latest`   | [1 year](https://en.wikipedia.org/wiki/MacOS_version_history#Releases)   |


<!-- TODO: once our e2e setup improves, also print a table of
tested Kubernetes flavours such as EKS, GKE, AKS, K3s -->

## Deprecation Strategy

**Replaced** methods/fns/constants are **not removed** between immediate versions (when they remain usable), but are **kept with deprecation attribute** that sticks around for at least **3 releases**:

For instance, we deprecated [`runtime::utils::try_flatten_applied`](https://github.com/kube-rs/kube-rs/blob/d0bf02f9c0783a3087b83633f2fa899d8539e91d/kube-runtime/src/utils/mod.rs) in `0.72.0`:

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

The deprecation note SHOULD point out viable alternatives.

## Interface Changes

Public interfaces from `kube` is currently allowed to change between **minor** versions, provided github release & [[changelog]] provides adequate guidance on the change, and the amount of user facing changes is minimized and trivialised. In particular:

- changes needed to user code should have a [diff code comment](https://github.com/kube-rs/kube-rs/releases/tag/0.73.0) on the change
- changes as a result of interface changes should be explained
- if changes affect controller-rs or version-rs, link to the fixing commit
- when renaming functions, removing arguments, changing imports, show what to search/replace

In general; we **prefer deprecations and duplication** of logic **if** it **avoids confusion**. But sometimes the least confusing thing to do is often just removing the old interface.


## Major Release 1.0

While we satisfy [client requirements](https://github.com/kubernetes/design-proposals-archive/blob/main/api-machinery/csi-new-client-library-procedure.md#client-support-level) for stability, we have not released a `1.0.0` version yet.

This is due to an unstable subset of advanced functionality, and one outstanding feature:

1. [protobuf serialization layer](https://github.com/kube-rs/kube-rs/issues/725) is unimplemented
2. advanced client usage with websockets is new and still experiencing light shifting
3. runtime features are improving and still shifting

Those are the primary reasons for not releasing a 1.0, but there are also external concerns:

- we depend on pre-1.0 libraries and upgrading these under semver would force major bumps
- the public async iterator interface is [still being stabilised in rust](https://github.com/rust-lang/rust/issues/79024)

Because of these conditions we unfortunately cannot say a lot about our planned release cadence after hitting 1.0, but it is [being discussed separately](https://github.com/kube-rs/kube-rs/issues/923).

As a result, we currently:

- **track** our breaking changes with [changelog-change labeled PRs](https://github.com/kube-rs/kube-rs/pulls?q=is%3Apr+label%3Achangelog-change+is%3Aclosed)
- **inform** on necessary changes in [releases](https://github.com/kube-rs/kube-rs/releases) and the [[changelog]]
- **carefully change** according to our [guidelines on interface changes](#interface-changes)
- **deprecate** according to our [deprecation strategy](#deprecation-strategy)

<!--
## Panic Policy
TODO: need to address this at some point.
-->

--8<-- "includes/abbreviations.md"
--8<-- "includes/links.md"

[//begin]: # "Autogenerated link references for markdown compatibility"
[changelog]: changelog "Changelog"
[//end]: # "Autogenerated link references"
