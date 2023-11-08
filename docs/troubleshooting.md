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

A [watcher] will expose [watcher::Error] as the error part of it's `Stream` items. If these errors are discarded, it might lead to a continuously failing and retrying program.

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
- __In-cluster__, frequent restarts of a large app with many spurious non-fatal condition can mask underlying problems.
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

--8<-- "includes/abbreviations.md"
--8<-- "includes/links.md"
