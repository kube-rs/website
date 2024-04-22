# Availability

This chapter is about strategies for improving controller availability and tail latencies.

## Motivation

Despite the common goals often set forth for application deployments, most `kube` controllers:

- can run in a single replica (default recommendation)
- can handle being killed, and be shifted to another node
- can handle minor downtime

This is due to a couple of properties:

- Rust images are often very small and will reschedule quickly
- watch streams re-initialise quickly with the current state on boot
- [[reconciler#idempotency]] means multiple repeat reconciliations are not problematic
- parallel execution mode of reconciliations makes restarts fast

These properties combined creates a low-overhead system that is normally quick to catch-up after being rescheduled, and offers a traditional Kubernetes __eventual consistency__ guarantee.

That said, this setup can struggle under strong consistency requirements:

- How fast do you expect your reconciler to react?
- Do you allow `30s` P95 downtimes from reschedules?

## Reactivity

If __average reactivity__ is your biggest concern, then traditional [[scaling]] and [[optimization]] strategies can help:

- Configure controller concurrency to avoid waiting for a reconciler slot
- Optimize the reconciler, avoid duplicated work
- Satisfy CPU requirements to avoid cgroup throttling

You can plot heatmaps of reconciliation times in grafana using standard [[observability#What Metrics]].

<!--TODO: can we measure time from watch event seen to watch event received by reconciler?-->

## High Availability

At a certain point, the slowdown caused by pod reschedules is going to dominate the latency metrics. Thus, having more than one replica (and having HA) is a requirement for further reducing tail latencies.

Unfortunately, scaling a controller is more complicated than adding another replica because all Kubernetes watches are effectively unsynchronised, competing consumers that are unaware of each other.

!!! warning "Scaling Replicas"

    It not recommended to set `replicas: 2` for an [[application]] running a normal `Controller` without leaders/shards, as this will cause both controller pods to reconcile the same objects, creating duplicate work and potential race conditions.

To safely operate with more than one pod, you must have __leadership of your domain__ and wait for such leadership to be acquired before commencing.

## Leader Election

Leader election (via [Kubernetes//Leases](https://kubernetes.io/docs/concepts/architecture/leases/)) allows having control over resources managed in-Kubernetes via Leases as distributed locking mechanisms.

The common solution to downtime based-problems is to use the `leader-with-lease` pattern, by having another controller replica in "standby mode", ready to takeover immediately without stepping on the toes of the other controller pod. We can do this by creating a `Lease`, and gating on the validity of the lease before doing the real work in the reconciler.

The natural expiration of `leases` means that you are required to periodically update them while your main pod (the leader) is active. When your pod is to be replaced, you can initiate a step down (and expire the lease), say after draining your work queue after receiving a `SIGTERM`. If your pod crashes, then the lease will expire naturally (albeit likely more slowly).

<!-- this feels unhelpful maybe
### Defacto Leadership

When running the default 1 replica controller have implictly created a `leader for life`. You never have other contenders for "defacto leadership" except for the short upgrade window:

!!! warning "Rollout Safety for Single Replicas"

    Even with 1 replica, you might see racey writes during controller upgrades without locking/leases. A `StatefulSet` with one replica could also give you a downtime based rolling upgrade that implicitly avoids racey writes, but it could also [require manual rollbacks](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/#forced-rollback).

Other forms of defacto leadership can come in the form of [shards](./scaling.md#Sharding), but these are generally created for [[scaling]] concerns, and suffer from the same problems during rollout and controller teardown.
-->

### Third Party Crates

At the moment, leader election support is not supported by `kube` itself, and requires 3rd party crates (see [kube#485](https://github.com/kube-rs/kube/issues/485#issuecomment-1837386565)). A brief list of popular crates:

- [`kube-leader-election`](https://crates.io/crates/kube-leader-election/) via [hendrikmaus](https://github.com/hendrikmaus/kube-leader-election) ([examples](https://github.com/hendrikmaus/kube-leader-election/tree/master/examples) / [docs](https://docs.rs/kube-leader-election/) / [disclaimer](https://github.com/hendrikmaus/kube-leader-election?tab=readme-ov-file#kubernetes-lease-locking))
- [`kube-coordinate`](https://crates.io/crates/kube-coordinate) via [thedodd](https://github.com/thedodd/kube-coordinate) ([docs](https://docs.rs/kube-coordinate/))
- [`kubert`](https://crates.io/crates/kubert) -> [`kubert::lease`](https://docs.rs/kubert/latest/kubert/lease/index.html) via [olix0r](https://github.com/olix0r/kubert) ([example](https://github.com/olix0r/kubert/blob/main/examples/lease.rs) / [linkerd use](https://github.com/linkerd/linkerd2/blob/1f4f4d417c6d06c3bd5a372fc75064f967117886/policy-controller/src/main.rs))

<!-- OTHER ALTERNATIVES???
Know other alternatives? Feel free to raise a PR here with a new list entry.
-->

### Elected Shards

Leader election can in-theory be used on top of explicit [[scaling#sharding]] to ensure you have at most one replica managing one shard by using one lease per shard. This could reduce the number of excess replicas standing-by in a sharded scenario.

--8<-- "includes/abbreviations.md"
--8<-- "includes/links.md"
