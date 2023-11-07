# Troubleshooting

## Kubernetes Access

Problems with [Api] commands failing is often RBAC or naming related and can be identified either in error codes or logs.

See [[observability#adding-logs]] for how to a tracing subscriber set-up so you can get `kube` logs printed.

### Access

Access issues bubble up as an [kube::Error::Api](https://docs.rs/kube/latest/kube/enum.Error.html#variant.Api) where the underlying error code will contain a `403`.

These will show up looking something like this when printed:

```sh
ErrorResponse { status: "Failure", message: "documents.kube.rs \"samuel\" is forbidden: User \"system:serviceaccount:default:doc-controller\" cannot patch resource \"documents\" in API group \"kube.rs\" in the namespace \"default\"", reason: "Forbidden", code: 403 }
```

And they should be visible directly (if you are printing your error objects somewhere rather than discarding them), or internally.


### Watcher Errors

An infinite [watcher] loop (see [[streams]]) will __retry on all failures__, but access errors are printed (with at least `RUST_LOG=warn` lower)

```sh
WARN kube_runtime::watcher: watcher error 403: Api(ErrorResponse { status: "Failure", message: "documents.kube.rs is forbidden: User \"system:serviceaccount:default:doc-controller\" cannot watch resource \"documents\" in API group \"kube.rs\" at the cluster scope", reason: "Forbidden", code: 403 })
```

so either make sure you have some sanity mechanism in place to catch this because a watcher stuck in an access problem will not get any data.

One common solution is to add metrics via [[observability#adding-metrics]] and track that your controller (or similar) always has work to do via periodic requeuing.

Another is to check for certain errors up front before starting an infinite watch stream; say by verifying you can do a naked list first;

```rust
if let Err(e) = docs.list(&ListParams::default().limit(1)).await {
    error!("CRD is not queryable; {e:?}. Is the CRD installed?");
    info!("Installation: cargo run --bin crdgen | kubectl apply -f -");
    std::process::exit(1);
}
```

### Request Inspection

If you are replicating functionality you can use from `kubectl`, then you can verify that what `kube` does is the same as `kubectl`.

Given an [example alpine pod](https://github.com/kube-rs/kube/blob/12bd223e0a7ef49c4ed0420a169e6c1bc3c1e214/examples/pod_exec.rs#L19-L29), we run `exec` on a shell loop, and use `-v=9` to look for a `curl` expression in a large (and abbreviated) amount of debug output to see what we actually tell the apiserver to do:

```sh
$ kubectl exec example -it -v=9 -- sh -c 'for i in $(seq 1 3); do date; done'
curl -v -XPOST -H "X-Stream-Protocol-Version: v4.channel.k8s.io" \
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
