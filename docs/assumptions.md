# Assumptions

Kube relies on a number of generally assumed invariants of Kubernetes.

We document these here openly as a show to Kubernetes devs about implicit expectations, and to our users about what non-typed contracts can cause `kube` to **panic**.

## Apiserver Invariants

Assumed non-optional fields:

- An object returned by the apiserver must have a non-empty `.metadata.name` (reflectors)
- An object sent to admission must have a non-empty `.metadata.name` OR a non-empty `.metadata.generateName` (admission controller example)
- Watch api contains an `.metadata.resourceVersion` for each non-error event (watcher)

## Object Invariants

TODO: pod/event/lease if any - can't find any relied upon ones

## Kube invariants

Helper functions ending in `_unchecked` have their own invariants that are documented internally.
