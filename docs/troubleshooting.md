# Troubleshooting

Problems with [Api] commands failing is often RBAC, misspelled names (used for url construction) and can be usually be identified via error codes and logs. Some common problems and solutions are explored herein.

!!! note "Logs are a prerequisite"

    See [[observability#adding-logs]] for how to setup tracing subscribers properly ([env_logger] works also).

## Request Inspection

If you are replicating `kubectl` behaviour, then you can cross-reference with logs.

Given an [example alpine pod](https://github.com/kube-rs/kube/blob/12bd223e0a7ef49c4ed0420a169e6c1bc3c1e214/examples/pod_exec.rs#L19-L29), we will run `exec` on a shell loop, and use `-v=9` to look for a `curl` expression in a large (and abbreviated) amount of debug output to see what we actually tell the apiserver to do:

```sh
$ kubectl exec example -it -v=9 -- sh -c 'for i in $(seq 1 3); do date; done'

round_trippers.go:466] curl -v -XPOST -H "X-Stream-Protocol-Version: v4.channel.k8s.io" \
  'https://0.0.0.0:64262/api/v1/namespaces/kube-system/pods/example/exec?command=sh&command=-c&command=for+i+in+%24%28seq+1+3%29%3B+do+date%3B+done&container=example&stdin=true&stdout=true&tty=true'
```

This url and query parameters can be cross-referenced in the logs from `kube_client`.

A very similar call is here being done [from the `pod_exec` example](https://github.com/kube-rs/kube/blob/12bd223e0a7ef49c4ed0420a169e6c1bc3c1e214/examples/pod_exec.rs#L57-L63), and when running with `RUST_LOG=debug` we can find a "requesting" debug line with the url used:

```sh
$ RUST_LOG=debug cargo run --example pod_exec
DEBUG HTTP{http.method=GET http.url=https://0.0.0.0:64262/api/v1/namespaces/kube-system/pods/example/exec?&stdout=true&command=sh&command=-c&command=for+i+in+%24%28seq+1+3%29%3B+do+date%3B+done otel.name="exec" otel.kind="client"}: kube_client::client::builder: requesting
```

Then we can investigate whether our query parameters matches what is expected (in this case stream differences and tty differences).

## Access

Access issues is a result of misconfigured access or lacking [[manifests#RBAC]] and will bubble up as a [kube::Error::Api](https://docs.rs/kube/latest/kube/enum.Error.html#variant.Api) where the underlying error code will contain a `403`.

In print, they look something like this:

```sh
ErrorResponse { status: "Failure", message: "documents.kube.rs \"samuel\" is forbidden: User \"system:serviceaccount:default:doc-controller\" cannot patch resource \"documents\" in API group \"kube.rs\" in the namespace \"default\"", reason: "Forbidden", code: 403 }
```

And they should be visible directly provided you are actully printing your error objects somewhere (rather than discarding them).

If you turn up logging to `RUST_LOG=kube=debug` you should also see most errors internally.

## Watcher Errors

A [watcher] will expose [watcher::Error] as the error part of it's `Stream` items. If these errors are discarded, it might lead to a continuously failing and retrying program. For a comprehensive treatment of error types across all layers and backoff configuration, see [[errors]].

!!! warning "Watcher errors are soft errors"

    A watcher will retry on all failures (including 403s, network failures) because the watcher can recover if external circumstances improve (for instance by an admin tweaking a `Role` object, or the network improving). These errors are therefore often __optimistically ignored__, but they should never be __silently ignored__.

When matching on items from the stream and printing the errors, the errors can look like:

```sh
WatchFailed(Api(ErrorResponse { status: "Failure", message: "ListOptions.meta.k8s.io \"\" is invalid: resourceVersionMatch: Forbidden: resourceVersionMatch is forbidden for watch", reason: "Invalid", code: 422 }))
```

If you are not printing the watcher errors yourself, you can get them via logs from `kube_runtime` (available with `RUST_LOG=warn` for the most common errors like RBAC, or `RUST_LOG=kube=debug` for the more obscure errors). It will look something like this:

```sh
WARN kube_runtime::watcher: watcher error 403: Api(ErrorResponse { status: "Failure", message: "documents.kube.rs is forbidden: User \"system:serviceaccount:default:doc-controller\" cannot watch resource \"documents\" in API group \"kube.rs\" at the cluster scope", reason: "Forbidden", code: 403 })
```

## Stream Errors

Because of the soft-error policy on stream errors, it's useful to consider what to do with errors in general from infinite streams.

The __easiest__ error handling setup is to tear down the application on any errors by (say) passing stream errors through a `try_for_each` (ala [pod_watcher](https://github.com/kube-rs/kube/blob/5813ad043e00e7b34de5e22a3fd983419ece2493/examples/pod_watcher.rs#L26-L33)) or a `try_next` loop (ala [event_watcher](https://github.com/kube-rs/kube/blob/5813ad043e00e7b34de5e22a3fd983419ece2493/examples/event_watcher.rs#L39-L43)).

!!! note "Crashing in-cluster"

    If you are deployed in-cluster, don't be afraid to exit(1)/crash early on errors you don't expect. Exits are easier to handle than a badly running app in a confusing state. By crashing, you get [retry with backoff](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#restart-policy) for free, plus you often get alerts such as [KubePodCrashLooping](https://runbooks.prometheus-operator.dev/runbooks/kubernetes/kubepodcrashlooping/) triggering (without instrumentation needed).

While easy, early exits is not the best solution;

- __Locally__, having a CLI abruptly exit is a bad user experience.
- __In-cluster__, frequent restarts of a large app with many spurious non-fatal conditions can mask underlying problems.
- early exits throw cancel-safety and state transaction concerns out the window

For controllers with multiple watchers, [[observability#Adding Metrics]] is instead customary, so that you can alert on percentage error rates over a time span (telling the operator to go look at logs for why).

It is also common to check for **blocker errors** up-front before starting an infinite watch stream;

1. did you install the crd before trying to start a watcher? do a naked list first as a sanity:

```rust
if let Err(e) = docs.list(&ListParams::default().limit(1)).await {
    error!("CRD is not queryable; {e:?}. Is the CRD installed?");
    info!("Installation: cargo run --bin crdgen | kubectl apply -f -");
    std::process::exit(1);
}
watcher(docs, conf).try_for_each(|_| future::ready(Ok(()))).await?;
```

This is a particularly common error case since CRD installation is often managed out-of-band with the application and thus often neglected.

## Common Symptoms

The sections above cover specific error types. Below are symptom-based tables for quickly diagnosing the most common operational issues.

### Reconciler Infinite Loop

**Symptom**: reconcile call count increases endlessly, high CPU usage.

| Cause | How to verify | Solution |
|-------|--------------|----------|
| Writing non-deterministic values to status (timestamps) | `RUST_LOG=kube=debug` — patch fires every reconcile | Use deterministic values; skip patch when unchanged |
| Missing [predicate_filter] | Reconcile logs show status-only changes triggering | Apply `predicate_filter(predicates::generation)` |
| Competing with another controller (annotation ping-pong) | `kubectl get -w` shows alternating `resourceVersion` updates | Use [[ssa]] to separate field ownership |

See [[optimization#repeatedly-triggering-yourself]] for a detailed explanation of self-triggering causes and fixes.

### Memory Keeps Growing

**Symptom**: higher than expected Pod memory.

| Cause | How to verify | Solution |
|-------|--------------|----------|
| Initial list allocations | High baseline memory after startup | Use `streaming_lists()`, or reduce `page_size` |
| Large objects in [Store] cache | Profile with jemalloc; check Store size | Use `.modify()` to strip `managedFields`, or switch to [metadata_watcher] |
| Watch scope too broad | Check `store.state().len()` for cached object count | Narrow scope with label/field selectors |

See [[optimization]] for detailed guidance.

### Watch Connection Not Recovering

**Symptom**: controller appears stuck, no events received.

| Cause | How to verify | Solution |
|-------|--------------|----------|
| 410 Gone without bookmarks | Log shows `WatchError` 410 | Watcher auto-recovers via re-list with `default_backoff()` |
| Credential expiry | Log shows 401/403 errors | Verify `Config::infer()` auto-refreshes; check exec plugin config |
| RBAC / NetworkPolicies | Log shows 403 Forbidden | Add watch/list permissions to ClusterRole; check NetworkPolicy allows egress to API server |
| Missing backoff | Stream terminates on first error | Always use `.default_backoff()` |

See [[errors]] for watcher backoff configuration and the full error handling guide.

### API Server Throttling (429)

**Symptom**: frequent `429 Too Many Requests` errors in logs.

| Cause | How to verify | Solution |
|-------|--------------|----------|
| Too many concurrent reconciles | Check active reconcile count via metrics | Set `controller::Config::concurrency(N)` |
| Too many watch connections | Count `owns()` and `watches()` calls | Use shared reflectors to share watches |
| Excessive API calls in reconciler | Trace HTTP request count per reconcile | Use [Store] cache reads; batch where possible |

### Finalizer Deadlock (Stuck Terminating)

**Symptom**: resource stays in `Terminating` state indefinitely.

| Cause | How to verify | Solution |
|-------|--------------|----------|
| Cleanup function keeps failing | Check logs for cleanup errors; monitor via `error_policy` metrics | Design cleanup to eventually succeed (treat missing external resources as success) |
| [predicate_filter] blocks finalizer events | Using `predicates::generation` only | Use `predicates::generation.combine(predicates::finalizers)` |
| Controller is down | Check pod status | Controller automatically processes on restart |

Emergency release: `kubectl patch <resource> -p '{"metadata":{"finalizers":null}}' --type=merge` (skips cleanup)

### Reconciler Not Running

**Symptom**: resource changes but no reconciler logs appear.

| Cause | How to verify | Solution |
|-------|--------------|----------|
| [Store] not yet initialized (advanced; only with [[streams]] interface) | Readiness probe fails | Wait for [Store::wait_until_ready] |
| [predicate_filter] blocks all events | Review predicate logic | Temporarily remove predicates to test |
| Insufficient RBAC permissions | Log shows 403 Forbidden | Add watch/list permissions to ClusterRole |
| NetworkPolicies blocking API server access | Connection timeouts in logs | Check NetworkPolicy allows egress to API server |
| Watcher selector too narrow | `kubectl get -l <selector>` returns nothing | Adjust selector |

## Debugging Tools

### RUST_LOG levels

```sh
# Basic debugging: kube internals + your controller
RUST_LOG=kube=debug,my_controller=debug

# Individual watch events (very verbose)
RUST_LOG=kube=trace

# HTTP request level
RUST_LOG=kube=debug,tower_http=debug

# Suppress noise
RUST_LOG=kube=warn,hyper=warn,my_controller=info
```

### tracing spans

The [Controller] automatically creates spans with `object.ref` and `object.reason`. With JSON logging enabled, you can filter by object:

```sh
cat logs.json | jq 'select(.span.object_ref | contains("my-resource-name"))'
```

See [[observability]] for setting up structured logging and traces.

### kubectl inspection

```sh
# Resource status and events
kubectl describe myresource <name>

# Watch for real-time changes
kubectl get myresource -w

# Track resourceVersion changes (diagnose infinite loops)
kubectl get myresource <name> -o jsonpath='{.metadata.resourceVersion}' -w

# Check finalizer state
kubectl get myresource <name> -o jsonpath='{.metadata.finalizers}'
```

## Profiling

### Memory profiling with jemalloc

```toml
[dependencies]
tikv-jemallocator = { version = "*", features = ["profiling"] }
```

```rust
#[global_allocator]
static ALLOC: tikv_jemallocator::Jemalloc = tikv_jemallocator::Jemalloc;
```

```sh
# Enable heap profiling
MALLOC_CONF="prof:true,prof_active:true,lg_prof_interval:30" ./my-controller

# Analyze profile dump
jeprof --svg ./my-controller jeprof.*.heap > heap.svg
```

If `AHashMap` allocations dominate the profile, the [Store] cache is the largest memory consumer. Apply `.modify()` or switch to [metadata_watcher].

### Async runtime profiling with tokio-console

If reconcilers are slow and you suspect async task scheduling, use [tokio-console](https://github.com/tokio-rs/console):

```toml
[dependencies]
console-subscriber = "*"
```

```rust
console_subscriber::init();
```

```sh
tokio-console http://localhost:6669
```

This shows per-task poll times, waker counts, and wait durations. If a reconciler task is blocked for long periods, look for synchronous operations or slow API calls inside it.

For lightweight runtime metrics without the TUI, consider [tokio-metrics](https://github.com/tokio-rs/tokio-metrics) which can export to Prometheus.

--8<-- "includes/abbreviations.md"
--8<-- "includes/links.md"

[//begin]: # "Autogenerated link references for markdown compatibility"
[ssa]: controllers/ssa "Server-Side Apply"
[errors]: controllers/errors "Error Handling"
[optimization]: controllers/optimization "Optimization"
[observability]: controllers/observability "Observability"
[manifests]: controllers/manifests "Manifests"
[streams]: controllers/streams "Streams"
[//end]: # "Autogenerated link references"
