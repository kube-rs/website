# Release Process

The release process for all the crates in kube is briefly outlined in [release.toml](https://github.com/kube-rs/kube-rs/blob/master/release.toml).

## Versioning

We currently release all crates with the same version.

The crates are thus **version-locked** and new version in certain [sub-crates](/crates) does not necessarily guarantee changes to that crate.
Our [[changelog]] considers changes to the facade crate `kube` as the highest importance.

The crates are published in reverse order of importance, releasing the final facade crate `kube` last, so users who depend on this do not notice any version-mismatches during releases.
## Cadence

We **currently** have **no fixed cadence**, but we still **try** to release **roughly once a month**, or whenever important PRs are merged (whichever is earliest).


## For maintainers: Cutting Releases

Cutting releases is a task for the maintenance team ([[contributing]]) and requires developer [[tools]] installed.

The process is automated where possible, and the non-writing bits usually only take a few minutes, whereas the management of documentation and release resources require a bit of manual oversight.

### Preliminary Steps

Close the [current ongoing milestone](https://github.com/kube-rs/kube-rs/milestones), and ensure the [prs merged since the last version](https://github.com/kube-rs/kube-rs/commits/master) are included in the milestone.

Ensure the PRs in the milestone all have exactly one `changelog-*` label to ensure the release notes are generated correctly (we follow [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) with the setup as outlined in [#754](https://github.com/kube-rs/kube-rs/issues/754)).

### Publishing Crates

Start the process by publishing to crates.io (crate-by-crate) **locally** with the **latest stable rust toolchain** installed and active:

```sh
PUBLISH_GRACE_SLEEP=20 cargo release minor --execute
```

once this completes, double check that all the crates are correctly published to crates.io:

- [kube-core](https://crates.io/crates/kube-core)
- [kube-derive](https://crates.io/crates/kube-derive)
- [kube-client](https://crates.io/crates/kube-client)
- [kube-runtime](https://crates.io/crates/kube-runtime)
- [kube](https://crates.io/crates/kube)

This will [enqueue a documentation build in docs.rs](https://docs.rs/releases/queue) to complete.

> Docs build usually completes in less than `30m`, but we have seen it take [around half a day](https://github.com/kube-rs/kube-rs/issues/665#issuecomment-949988895) when publishing during an anticipated rust release.

### Generating the release

Once the crates have been published, we can start the process for creating a [GitHub Release](https://github.com/kube-rs/kube-rs/releases).

If you just published, you will have at least one commit unpushed locally. You can push and tag this in one go using it:

```sh
./scripts/release-post.sh
```

This creates a tag, and a **draft** release using our [release workflow](https://github.com/kube-rs/kube-rs/actions/workflows/release.yml).
The resulting github **release** will show up on [kube-rs/releases](https://github.com/kube-rs/kube-rs/releases) immediately.

However, we should **not publish** this until the [enqueued documentation build in docs.rs](https://docs.rs/releases/queue) completes.

We use this wait-time to fully prepare the release, and write the manual release header:

### Editing the draft

At this point we can edit the draft release. Click the edit release pencil icon, and start editing.

You will notice **auto-generated notes already present** in the `textarea` along with new contributors - **please leave these lines intact**!

Check if any of the PRs in the release contain any notices or are particularly noteworthy.
We strongly advocate for highlighting some or more of the following, as part of the manually written header:

- big features
- big fixes
- contributor recognition
- interface changes

> A release is more than just a `git tag`, it should be something to **celebrate**, for the maintainers, the contributors, and the community.

See the appendix below for ideas.

Of course, not every release is going to be noteworthy.
For these cases, it's perfectly OK to just hit [Publish](#){ .md-button-primary } without much ceremony.

### Completion Steps

- Create a [new milestone](https://github.com/kube-rs/kube-rs/milestones) for current minor version + 1
- Press [Publish](#){ .md-button-primary } on the release once [docs.rs build completes](https://docs.rs/releases/queue)
- Run `./scripts/release-afterdoc.sh` to port the changed release notes into the `CHANGELOG.md` and push
- Run `./sync.sh` in the website repo to port the new release notes onto the website

## Appendix

### Header Formatting Tips

Some example release notes from recent history has some ideas:

- [0.68.0](https://github.com/kube-rs/kube-rs/releases/tag/0.68.0)
- [0.66.0](https://github.com/kube-rs/kube-rs/releases/tag/0.66.0)

Note that headers should link to PRs/important documents, but it is not necessary to link into the release or the milestone in this document yourself (the `afterdoc` step automates this).

For breaking changes; consider including migration code samples for users if it provides an easier way to understand the changes. Fenced code blocks with `diff` language are easy to scan:

```diff
-async fn reconcile(myobj: MyK, ctx: Arc<Data>) -> Result<ReconcilerAction>
+async fn reconcile(myobj: Arc<MyK>, ctx: Arc<Data>) -> Result<ReconcilerAction>
```

New features should link to the new additions under docs.rs/kube once the documentation build completes.

...

[//begin]: # "Autogenerated link references for markdown compatibility"
[changelog]: changelog "Changelog"
[contributing]: contributing "Contributing Guide"
[tools]: tools "Tools"
[//end]: # "Autogenerated link references"
