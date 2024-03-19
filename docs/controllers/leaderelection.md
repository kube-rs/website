# Leader Election

This chapter is a stub about Leases, Leader Election and how to achieve distributed locks around Kubernetes resources.

!!! note "Terminology"

    See [Kubernetes//Leases](https://kubernetes.io/docs/concepts/architecture/leases/) for introductory definitions.

## Requirements

Despite the common goals often set forth for application deployments, most `kube` controllers:

- can run in a single replica (this is the default recommendation)
- can handle being killed, and be shifted to another node
- can handle minor downtime

This is due to a couple of properties:

- Rust controllers are generally very efficient and often end up as IO bound
- watch streams re-initialise with the current state on boot
- [[reconciler#idempotency]] means multiple repeat reconciliations are not problematic
- parallel execution mode of reconciliations makes restarts fast

These properties combined creates a system that can scale very well, is normally quick to catch-up after being rescheduled, and offers a traditional Kubernetes __eventual consistency__ guarantee.

That said, this philosophy can struggle when given more intensive requirements like:

- your reconcilers need to do a lot of heavy memory/CPU bound work per reconciliation
- your reconcilers manages enough objects that [flow-control](https://kubernetes.io/docs/concepts/cluster-administration/flow-control/) / throttling is a concern
- your requirement for consistency is strong enough that even a P95 `30s` downtime from a reschedule is problematic

In these cases, you are limited by the amount of work a controller running on a single bounded pod can realistically accomplish. In these cases, scaling is desireable.

!!! warn "Leader election is not a requirement for scaling"

    When running the default 1 replica controller you have a de-facto `leader for life`. Unless you have strong consistency requirements, many problems can be avoided using [[optimization]] techniques.

<!-- TODO: what rollout settings do we recommend for 1 replica controllers to avoid race conditions?
apparently you cannot set both maxSurge: 0 and maxUnavailable: 0 - https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#rolling-update-deployment
-->

## Scaling Safely

The common solution to downtime based-problems is to use the `leader-with-lease` pattern, by having allowing another controller replica in "standby mode", ready to takeover immediately without stepping on the toes of the other controller pod. We can do this by creating a `Lease`, and gating on the validity of the lease before doing the real work in the reconciler.

!!! warn "Scaling controllers"

    It not recommended to just set `replicas: 2` for an [[application]] running a normal `Controller`, as this will cause both controller pods to reconcile the same objects, creating duplicate work and potential race conditions.

The natural expiration of `leases` means that you are required to periodically update them while your main pod (the leader) is active. When your pod is to be replaced, you can initiate a step down (and expire the lease), say when you receive a `SIGTERM`.

<!--
## Scaling Partitioning

Having another pod ready to step in only solves the problem of periodic downtime, not resource constraints from having an extremely busy reconciler. If you need to actually scale a controller for such a scenario, then leases can be used in more sophisticated ways to partition the space you are reconciling, and have each replica be responsible for each partition silo.

TODO: is this actually used? i have not seen it, but i imagined this is what people would use for advanced scaling ^^
NB: This part of the document is not shown, just a note to self to revisit this if we see such a pattern.
-->

## Crates

At the moment, leader election support is not supported by `kube` itself, and requires 3rd party crates (see [kube#485](https://github.com/kube-rs/kube/issues/485#issuecomment-1837386565)).

### kube-leader-election
The [`kube-leader-election` crate](https://crates.io/crates/kube-leader-election/) via [hendrikmaus/kube-leader-election](https://github.com/hendrikmaus/kube-leader-election) is a small crate that allows for rudimentary leader election with a [use-case disclaimer](https://github.com/hendrikmaus/kube-leader-election?tab=readme-ov-file#kubernetes-lease-locking).

```rust
use kube_leader_election::{LeaseLock, LeaseLockParams};
let leadership = LeaseLock::new(client, namespace, LeaseLockParams { ... });
let _lease = leadership.try_acquire_or_renew().await?;
leadership.step_down().await?;
```

It has [examples](https://github.com/hendrikmaus/kube-leader-election/tree/master/examples), documented at [docs.rs/kube-leader-election](https://docs.rs/kube-leader-election/)

### kube-coordinate
The [`kube-coordinate` crate](https://crates.io/crates/kube-coordinate) via [thedodd/kube-coordinate](https://github.com/thedodd/kube-coordinate) is implements a larger, more configurable abstraction, that allows passing the state around:

```rust
use kube_coordinate::{LeaderElector, Config};
let handle = LeaderElector::spawn(Config {...}, client);
let state_chan = handle.state();
if state_chan.borrow().is_leader() {
    // Only perform leader actions if in leader state.
}
```

It is documented at [docs.rs/kube-coordinate](https://docs.rs/kube-coordinate/).

### kubert
The [`kubert` crate](https://github.com/olix0r/kubert) via [olix0r/kubert](https://github.com/olix0r/kubert) is linkerd's utility crate. It contains a low-level `lease` module.

```rust
use kubert::lease::{ClaimParams, LeaseManager};
let lease_api: Api<Lease> = Api::namespaced(client, namespace);
let lease = LeaseManager::init(lease_api, name).await?;
let claim = lease.ensure_claimed(&identity, &ClaimParams { ... }).await?;
assert!(claim.is_current_for(&identity));
```

It is documented at [docs.rs/kubert/lease](https://docs.rs/kubert/latest/kubert/lease/index.html), has a [large lease example](https://github.com/olix0r/kubert/blob/main/examples/lease.rs), and used by [linkerd's policy-controller](https://github.com/linkerd/linkerd2/blob/1f4f4d417c6d06c3bd5a372fc75064f967117886/policy-controller/src/main.rs).


<!-- OTHER ALTERNATIVES???
Know other alternatives? Feel free to raise a PR here with a new H3 entry.

Try to follow roughly the short and (ideally) minimally subjective format above.
-->


--8<-- "includes/abbreviations.md"
--8<-- "includes/links.md"
