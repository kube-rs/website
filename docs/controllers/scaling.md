# Scaling

This chapter is about scaling advice, strategies, and how to achieve distributed locks around Kubernetes resources.

## When to Scale

Despite the common goals often set forth for application deployments, most `kube` controllers:

- can run in a single replica (this is the default recommendation)
- can handle being killed, and be shifted to another node
- can handle minor downtime

This is due to a couple of properties:

- Rust controllers are generally very efficient and often end up as IO bound
- Rust images are often very small and will reschedule quickly
- watch streams re-initialise with the current state on boot
- [[reconciler#idempotency]] means multiple repeat reconciliations are not problematic
- parallel execution mode of reconciliations makes restarts fast

These properties combined creates a system that can scale very well, is normally quick to catch-up after being rescheduled, and offers a traditional Kubernetes __eventual consistency__ guarantee.
That said, this philosophy can struggle when given more intensive requirements like:

- your reconcilers need to do a lot of heavy memory/CPU bound work per reconciliation
- your reconcilers manages enough objects that [flow-control](https://kubernetes.io/docs/concepts/cluster-administration/flow-control/) / throttling is a concern
- your requirement for consistency is strong enough that even a P95 `30s` downtime from a reschedule is problematic

In these cases, you are limited by the amount of work a controller running on a single bounded pod can realistically accomplish. In these cases, scaling is desireable.

## Scaling Strategies
We recommend trying the following scaling strategies in order.

### 1. Controller Optimizations
Ensure you look at common controller [[optimizations]] to:

* minimize network intensive operations
* cache/memoize expensive work
* checkpoint progress on `.status` objects to avoid repeating work

When checkpointing, care should be taken to not accidentally break [[reconciler#idempotency]].

### 2. Vertical Scaling

* increase cpu/memory limits
* configure controller concurrency (as a multiple of CPU limits)

The [controller::Config] by currently[**](https://github.com/kube-rs/kube/issues/1473) defaults to __unlimited concurrency__ and may need tuning for large workloads.

It is __possible__ to compute an optimal `concurrency` number based the CPU `resources` you assign to your container, but this would require specific measurement against your workload.

!!! note "Agressiveness meets fairness"

    A highly parallel reconciler might be eventually throttled by [apiserver flow-control rules](https://kubernetes.io/docs/concepts/cluster-administration/flow-control/), and this can clearly degrade your controller's performance. Measurements, calculations, and [[observability]] (particularly for error rates) are useful to identifying such scenarios.

### 3. Leader Election
Leader election allows having control over resources managed in-Kubernetes via Leases and allows for faster response times on pod rescheduling.

!!! note "Terminology"

    See [Kubernetes//Leases](https://kubernetes.io/docs/concepts/architecture/leases/) for introductory definitions.

The common solution to downtime based-problems is to use the `leader-with-lease` pattern, by having allowing another controller replica in "standby mode", ready to takeover immediately without stepping on the toes of the other controller pod. We can do this by creating a `Lease`, and gating on the validity of the lease before doing the real work in the reconciler.

!!! warning "Scaling replicas"

    It not recommended to set `replicas: 2` for an [[application]] running a normal `Controller` without leaders/shards, as this will cause both controller pods to reconcile the same objects, creating duplicate work and potential race conditions.

<!-- TODO: what rollout settings do we recommend for 1 replica controllers to avoid race conditions?
apparently you cannot set both maxSurge: 0 and maxUnavailable: 0 - https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#rolling-update-deployment
-->

The natural expiration of `leases` means that you are required to periodically update them while your main pod (the leader) is active. When your pod is to be replaced, you can initiate a step down (and expire the lease), say when you receive a `SIGTERM`. If your pod crashes, then the lease will expire naturally (albeit likely more slowly).

!!! warn "Leader election is not a requirement for scaling"

    When running the default 1 replica controller you have a de-facto `leader for life`. Unless you have strong latency/consistency requirements, leader election is not a required solution.

At the moment, leader election support is not supported by `kube` itself, and requires 3rd party crates (see [kube#485](https://github.com/kube-rs/kube/issues/485#issuecomment-1837386565)). A brief list of popular crates:

#### [`kube-leader-election`](https://crates.io/crates/kube-leader-election/)
A small standalone crate with a [use-case disclaimer](https://github.com/hendrikmaus/kube-leader-election?tab=readme-ov-file#kubernetes-lease-locking).
Via [hendrikmaus/kube-leader-election](https://github.com/hendrikmaus/kube-leader-election) ([examples](https://github.com/hendrikmaus/kube-leader-election/tree/master/examples) / [docs](https://docs.rs/kube-leader-election/)).

```rust
use kube_leader_election::{LeaseLock, LeaseLockParams};
let leadership = LeaseLock::new(client, namespace, LeaseLockParams { ... });
let _lease = leadership.try_acquire_or_renew().await?;
leadership.step_down().await?;
```
#### [`kube-coordinate`](https://crates.io/crates/kube-coordinate)
Standalone crate. Via [thedodd/kube-coordinate](https://github.com/thedodd/kube-coordinate) ([docs](https://docs.rs/kube-coordinate/)).

```rust
use kube_coordinate::{LeaderElector, Config};
let handle = LeaderElector::spawn(Config {...}, client);
let state_chan = handle.state();
if state_chan.borrow().is_leader() {
    // Only perform leader actions if in leader state.
}
```

#### [`kubert`](https://github.com/olix0r/kubert)
A utility crate containing a low-level `lease` module used by [linkerd's policy-controller](https://github.com/linkerd/linkerd2/blob/1f4f4d417c6d06c3bd5a372fc75064f967117886/policy-controller/src/main.rs).
Via [olix0r/kubert](https://github.com/olix0r/kubert) ([docs](https://docs.rs/kubert/latest/kubert/lease/index.html) / [example](https://github.com/olix0r/kubert/blob/main/examples/lease.rs))

```rust
use kubert::lease::{ClaimParams, LeaseManager};
let lease_api: Api<Lease> = Api::namespaced(client, namespace);
let lease = LeaseManager::init(lease_api, name).await?;
let claim = lease.ensure_claimed(&identity, &ClaimParams { ... }).await?;
assert!(claim.is_current_for(&identity));
```

<!-- OTHER ALTERNATIVES???
Know other alternatives? Feel free to raise a PR here with a new H3 entry.

Try to follow roughly the short and (ideally) minimally subjective format above.
-->

### 4. Sharding

If you are unable to meet latency/resource requirements using techniques above, you may need to consider **partitioning/sharding** your resources. Below are two commonly seen approaches for sharding:

* 1 controller deployment per namespace (naive and annoying to deploy)
* 1 controller replica per shard (precise, easier to scale, but requires labelling work)

A famous example of the last pattern is [fluxcd](https://fluxcd.io/). Flux exposes a [sharding.fluxcd.io/key label](https://fluxcd.io/flux/installation/configuration/sharding/) to configure sharding. Flux's Stefan talks about [scaling flux controllers at kubecon 2024](https://www.youtube.com/watch?v=JFLNFJT59DY).

!!! note "Leader Election with Shards"

    Leader election can be used on top of sharding to ensure you have at most one pod managing one shard.
    We have not seen any known examples of this in the wild. Links are welcome.

A mutating admission policy can help automatically assign/label partitions cluster-wide based on constraints and rebalancing needs.



--8<-- "includes/abbreviations.md"
--8<-- "includes/links.md"
