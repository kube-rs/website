# Scaling

This chapter is about strategies for scaling controllers and the tradeoffs these strategies make.

## Motivating Questions

- Why is the reconciler lagging? Are there too many resources being reconciled?
  * How do you find out?
- What happens when your controller starts managing resource sets so large that it starts significantly impacting your CPU or memory use?
  * Do you give your more resources?
  * Do you add more pods? How can you do this safely?

Scaling an efficient Rust application that spends most of its time waiting for network changes might not seem like a complicated affair, and indeed, you can scale a controller in many ways and achieve good outcomes. But in terms of costs, not all solutions are created equal; are you avoiding improving your algorithm, or are you throwing more expensive machines at the problem?

## Scaling Strategies

We recommend trying the following scaling strategies in order:

1. [[#Controller Optimizations]] (minimize expensive work to allow more work)
2. [[#Vertical Scaling]] (more headroom for the single pod)
3. [[#Sharding]] (horizontal scaling)

In other words, try to improve your algorithm first, and once you've reached a reasonable limit of what you can achieve with that approach, allocate more resources to the problem.

### Controller Optimizations
Ensure you look at common controller [[optimization]] to get the most out of your resources:

* minimize network intensive operations
* avoid caching large manifests unnecessarily, and prune unneeded data
* cache/memoize expensive work
* checkpoint progress on `.status` objects to avoid repeating work

When checkpointing, care should be taken to not accidentally break [[reconciler#idempotency]].

### Vertical Scaling

* increase CPU/memory limits
* configure controller concurrency (as a multiple of CPU limits)

The [controller::Config] currently[**](https://github.com/kube-rs/kube/issues/1473) defaults to __unlimited concurrency__ and may need tuning for large workloads.

It is __possible__ to compute an optimal `concurrency` number based the CPU `resources` you assign to your container, but this would require specific measurement against your workload.

!!! note "Agressiveness meets fairness"

    A highly parallel reconciler might be eventually throttled by [apiserver flow-control rules](https://kubernetes.io/docs/concepts/cluster-administration/flow-control/), and this can clearly degrade your controller's performance. Measurements, calculations, and [[observability]] (particularly for error rates) are useful to identifying such scenarios.

### Sharding

If you are unable to meet latency/resource requirements using techniques above, you may need to consider **partitioning/sharding** your resources.

Sharding is splitting your workload into mutually exclusive groups that you grant exclusive access to. In Kubernetes, shards are commonly seen as a side-effect of certain deployment strategies:

* sidecars :: pods are shards
* daemonsets :: nodes are shards

!!! note "Sidecars and Daemonsets"

    Several big agents use daemonsets and sidecars in situations that require higher than average performance, and is commonly found in network components, service meshes, and sometimes observability collectors that benefit from co-location with a resource. This choice creates a very broad and responsive sharding strategy, but one that incurs a larger overhead using more containers than is technically necessary.

Sharding can also be done in a more explicit way:

* 1 controller deployment per namespace (naive sharding)
* 1 controller deployment per shard (precice, but requires labelling work)

Explicitly labelled shards is a less common, but powerful option employed by [fluxcd](https://fluxcd.io/). Flux exposes a [sharding.fluxcd.io/key label](https://fluxcd.io/flux/installation/configuration/sharding/) to associate a resource with a shard. Flux's Stefan talks about [scaling flux controllers at KubeCon 2024](https://www.youtube.com/watch?v=JFLNFJT59DY).

!!! note "Automatic Labelling"

    A mutating admission policy can help automatically assign/label partitions cluster-wide based on constraints and rebalancing needs.

In cases where HA is required, a leases can be used gate access to a particular shard. See [[availability#Leader Election]]

--8<-- "includes/abbreviations.md"
--8<-- "includes/links.md"
