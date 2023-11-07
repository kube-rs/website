# Troubleshooting

Problems with [Api] commands failing is often RBAC or naming related and can be identified either in error codes or logs. Some common problems are explored herein.

See [[observability#adding-logs]] for how to a tracing subscriber set-up so you can get `kube` logs printed.

## Access

Access issues is a result of misconfigured or lacking [[manifests#RBAC]] and will bubble up as a [kube::Error::Api](https://docs.rs/kube/latest/kube/enum.Error.html#variant.Api) where the underlying error code will contain a `403`.

These will show up looking something like this when printed:

```sh
ErrorResponse { status: "Failure", message: "documents.kube.rs \"samuel\" is forbidden: User \"system:serviceaccount:default:doc-controller\" cannot patch resource \"documents\" in API group \"kube.rs\" in the namespace \"default\"", reason: "Forbidden", code: 403 }
```

And they should be visible directly (if you are printing your error objects somewhere rather than discarding them), or internally.


### Watcher Errors

A [watcher] will expose [watcher::Error] as the error part of it's `Stream` items. If these errors are discarded, it might lead to a continuously failing and retrying program.

!!! warning "Watcher errors are soft errors"

    A watcher will retry on all failures (including 403s, network failures) because the watcher can recover if external circumstances improve (for instance by an admin tweaking a `Role` object, or the network improving). These errors are therefore often ignored optimistically, but they should __never be silently ignored__.

When matching on items from the stream and printing the errors, the errors can look like:

```sh
WatchFailed(Api(ErrorResponse { status: "Failure", message: "ListOptions.meta.k8s.io \"\" is invalid: resourceVersionMatch: Forbidden: resourceVersionMatch is forbidden for watch", reason: "Invalid", code: 422 }))
```

If you are not printing the watcher errors yourself, you can get them via logs from `kube_runtime` (available with `RUST_LOG=warn` for the most common errors like RBAC, or `RUST_LOG=kube=debug` for the more obscure errors). It will look something like this:

```sh
WARN kube_runtime::watcher: watcher error 403: Api(ErrorResponse { status: "Failure", message: "documents.kube.rs is forbidden: User \"system:serviceaccount:default:doc-controller\" cannot watch resource \"documents\" in API group \"kube.rs\" at the cluster scope", reason: "Forbidden", code: 403 })
```

The easiest error handling is to tear down the application on any errors by i.e. passing stream errors through a `try_for_each` (ala [pod_watcher](https://github.com/kube-rs/kube/blob/5813ad043e00e7b34de5e22a3fd983419ece2493/examples/pod_watcher.rs#L26-L33)). This will usually let you know something is broken by crashing. Usually this either annoys the user, or it triggers the common [KubePodCrashLooping](https://runbooks.prometheus-operator.dev/runbooks/kubernetes/kubepodcrashlooping/) alert if you are deployed in-cluster. In both cases, this is an inelegant way of handling errors since it means you will also restart the full application on spurious network issues.

More error handling solutions is to try to handle errors for a while, but report them up to your environment. When deployed in-cluster, [[obervability#adding-metrics]] is the normal path, so you can alert on a higher than normal error rates (if they persist).


<!-- TODO: will move this to another productionising document later i think

Another is to check for the most common error up front before starting an infinite watch stream;

1. did you install the crd before trying to start a watcher? do a naked list first and exit if not:

```rust
if let Err(e) = docs.list(&ListParams::default().limit(1)).await {
    error!("CRD is not queryable; {e:?}. Is the CRD installed?");
    info!("Installation: cargo run --bin crdgen | kubectl apply -f -");
    std::process::exit(1);
}
```
-->

### Request Inspection

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

--8<-- "includes/abbreviations.md"
--8<-- "includes/links.md"
