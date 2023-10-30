# Troubleshooting

## Kubernetes Access

Problems with [Api] commands failing is often RBAC or naming related and can be identified either in error codes or logs.

### Cross-referencing with kubectl

If you are replicating functionality you can use from `kubectl`, then you can verify that what `kube` does is the same as `kubectl`.

Given an [example alpine pod](https://github.com/kube-rs/kube/blob/12bd223e0a7ef49c4ed0420a169e6c1bc3c1e214/examples/pod_exec.rs#L19-L29), we run `exec` on a shell loop, and use `-v=9` to look for a `curl` expression in a large (and abbreviated) amount of debug output to see what we actually tell the apiserver to do:

```sh
$ kubectl exec example -it -v=9 -- sh -c 'for i in $(seq 1 3); do date; done'
curl -v -XPOST -H "X-Stream-Protocol-Version: v4.channel.k8s.io" \
  'https://0.0.0.0:64262/api/v1/namespaces/kube-system/pods/example/exec?command=sh&command=-c&command=for+i+in+%24%28seq+1+3%29%3B+do+date%3B+done&container=example&stdin=true&stdout=true&tty=true'
```

This url and query parameters can be cross-referenced in a rust application with log instrumentation (see [[observability#adding-logs]]).

A very similar call is here being done [from the `pod_exec` example](https://github.com/kube-rs/kube/blob/12bd223e0a7ef49c4ed0420a169e6c1bc3c1e214/examples/pod_exec.rs#L57-L63), and when running with `RUST_LOG=debug` we can find a "requesting" debug line with the url used:

```sh
$ RUST_LOG=debug cargo run --example pod_exec
DEBUG HTTP{http.method=GET http.url=https://0.0.0.0:64262/api/v1/namespaces/kube-system/pods/example/exec?&stdout=true&command=sh&command=-c&command=for+i+in+%24%28seq+1+3%29%3B+do+date%3B+done otel.name="exec" otel.kind="client"}: kube_client::client::builder: requesting
```

Then we can investigate whether our query parameters matches what is expected (in this case stream differences and tty differences).

--8<-- "includes/abbreviations.md"
--8<-- "includes/links.md"
