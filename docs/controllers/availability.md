# Availability

This chapter is about strategies for improving controller availability and tail latencies.

## Motivation

Despite the common goals often set forth for application deployments, most `kube` controllers:

- can run in a single replica (default recommendation)
- can handle being killed, and be shifted to another node
- can handle minor downtime

This is due to a couple of properties:

- Controllers are queue consumers that do not require 100% uptime to meet a 100% SLO
- Rust images are often very small and will reschedule quickly
- watch streams re-initialise quickly with the current state on boot
- [[reconciler#idempotency]] means multiple repeat reconciliations are not problematic
- parallel execution mode of reconciliations makes restarts fast

These properties combined creates a low-overhead system that is normally quick to catch-up after being rescheduled, and offers a traditional Kubernetes __eventual consistency__ guarantee.

That said, this setup can struggle under strong consistency requirements. Ask yourself:

- How quickly do you expect your reconciler to **respond** to changes on average?
- Is a `30s` P95 downtime from reschedules acceptable?

## Responsiveness

If you want to improve __average responsiveness__, then traditional [[scaling]] and [[optimization]] strategies can help:

- Configure controller concurrency to avoid waiting for a reconciler slot
- Optimize the reconciler, avoid duplicated work
- Satisfy CPU requirements to avoid cgroup throttling

You can plot heatmaps of reconciliation times in grafana using standard [[observability#What Metrics]].

<!--TODO: can we measure time from watch event seen to watch event received by reconciler?-->

## High Availability

Scaling a controller beyond one replica for HA is different than for a regular load-balanced traffic receiving application.

A controller is effectively a consumer of Kubernetes watch events, and these are themselves unsynchronised event streams whose watchers are unaware of each other. Adding another pod - without some form of external locking - will result in duplicated work.

To avoid this, most controllers lean into the eventual consistency model and run with a single replica, accepting higher tail latencies due to reschedules. However, once the performance demands are strong enough, these pod reschedules will dominate the tail of your latency metrics, making scaling necessary.

!!! warning "Scaling Replicas"

    It not recommended to set `replicas: 2` for an [[application]] running a normal `Controller` without leaders/shards, as this will cause both controller pods to reconcile the same objects, creating duplicate work and potential race conditions.

To safely operate with more than one pod, you must have __leadership of your domain__ and wait for such leadership to be __acquired__ before commencing. This is the concept of leader election.

## Leader Election

Leader election allows having control over resources managed in Kubernetes using [Leases](https://kubernetes.io/docs/concepts/architecture/leases/) as distributed locking mechanisms.

The common solution to downtime based-problems is to use the `leader-with-lease` pattern, by having another controller replica in "standby mode", ready to takeover immediately without stepping on the toes of the other controller pod. We can do this by creating a `Lease`, and gating on the validity of the lease before doing the real work in the reconciler.

!!! note "Unsynchronised Rollout Surges"

    A 1 replica controller deployment without leader election might create short periods of duplicate work and racey writes during rollouts because of how [rolling updates surge](https://docs.rs/k8s-openapi/latest/k8s_openapi/api/apps/v1/struct.RollingUpdateDeployment.html) by default.

The natural expiration of `leases` means that you are required to periodically update them while your main pod (the leader) is active. When your pod is about be replaced, you can initiate a step down (and expire the lease), ideally after receiving a `SIGTERM` after [draining your active work queue](https://docs.rs/kube/latest/kube/runtime/struct.Controller.html#method.shutdown_on_signal). If your pod crashes, then a replacement pod must wait for the scheduled lease expiry.

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

<!-- Have examples?
Feel free to raise a PR here with information.
-->

--8<-- "includes/abbreviations.md"
--8<-- "includes/links.md"
