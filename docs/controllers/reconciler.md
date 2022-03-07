# Reconciler WIP


The reconciler is the warmest user-defined code in your controller, and it will end up doing a range of tasks.

## Using Context

- extracting a `Client` or an `Api` from the `Data`


## Idempotency

!!! warning "A reconciler must be [idempotent](https://en.wikipedia.org/wiki/Idempotence)"

    If a reconciler is triggered twice for the same object, it should cause the same outcome. Care must be taken to not repeat expensive api calls when unnecessary, and the flow of the reconciler must be able to recover from errors occurring in a previous reconcile run.

## OwnerReferences

## Finalizers

## Observability

- tracing instrumentation of the fn
- metrics

## Diagnostics

- api updates to the `object`'s **status struct**
- `Event` records populated for diagnostic informatio
