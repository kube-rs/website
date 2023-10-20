# Manifests

This chapter is about deployment manifests and common properties you want to set.

## RBAC

A Kubernetes `Role` / `ClusterRole` (with an associated binding) is necessary for your controller to function in-cluster. Below we list the common rules you need for the basics:

```yaml
rules:
# You want access to your CRD if you have one
# Replace documents with plural resource name, and kube.rs with your group
- apiGroups: ["kube.rs"]
  resources: ["documents", "documents/status"]
  verbs: ["get", "list", "watch", "patch"]

# If you want events
- apiGroups: ["events.k8s.io"]
  resources: ["events"]
  verbs: ["create"]
```

<!--
# If you want TBD leader election
- apiGroups: ["coordination.k8s.io"]
  resources: ["leases"]
  verbs: ["create", "delete", "get", "list", "patch", "watch"]
-->

See [controller-rs/rbac](https://github.com/kube-rs/controller-rs/blob/main/charts/doc-controller/templates/rbac.yaml) for how to hook this up with `helm`.

See [[security#Access Constriction]] to ensure the setup is as strict as is needed.

!!! note "Two Event structs"

    The runtime event [Recorder] uses the modern [events.k8s.io.v1.Event](https://kubernetes.io/docs/reference/kubernetes-api/cluster-resources/event-v1/) not to be mistaken for the legacy [core.v1.Event](https://docs.rs/k8s-openapi/latest/k8s_openapi/api/core/v1/struct.Event.html).

We do not provide any hooks to generate RBAC from Rust source ([it's not super helpful](https://github.com/kube-rs/kube/issues/1115)), so it is expected you put the various rules you need straight in your chart templates / jsonnet etc.

## Network Policy

To reduce unnecessary access from and to your controller, it is a good [[Security]] practice to use [network policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/).

We will showcase a **starter** `netpol` here that allows for pushing telemetry data to an otel collector, DNS queries, talking to the Kubernetes apiserver, and having metrics scraped by a prometheus server.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: kube-rs-controller
  labels:
    app: kube-rs-controller
  namespace: controllers
spec:
  egress:
  # For pushing tracing spans to an opentelemetry collector
  - to:
    - ports:
      # jaeger thrift
      - port: 14268
        protocol: TCP
      # OTLP gRPC
      - port: 4317
        protocol: TCP
      # OTLP HTTP
      - port: 4318
        protocol: TCP
      # zipkin
      - port: 9411
        protocol: TCP
      to:
    - namespaceSelector:
        matchLabels:
          name: opentelemetry-operator-system

  # For Kubernetes apiserver access
  - to:
    - ports:
      # Port depends on targetPort listed on kubernetes svc in default ns
      - port: 443
        protocol: TCP
      - port: 6443
        protocol: TCP
    - namespaceSelector:
        matchLabels:
          name: default

  # DNS egress
  - to:
    - podSelector:
        matchLabels:
          k8s-app: kube-dns
      ports:
      - port: 53
        protocol: UDP

  ingress:
  # For prometheus scraping support
  - from:
    - namespaceSelector:
        matchLabels:
          name: monitoring
      podSelector:
        matchLabels:
          app: prometheus
    ports:
    - port: http
      protocol: TCP

  # Policy properties
  podSelector:
    matchLabels:
      app: kube-rs-controller
  policyTypes:
  - Ingress
  - Egress
```

Adjust your app labels, names, namespaces, and ingress port names to your own values. Note that:

- [apiserver access can be done by ip](https://stackoverflow.com/questions/50102943/how-to-allow-access-to-kubernetes-api-using-egress-network-policy) - incorrect policies will yield "failed with error error trying to connect: deadline has elapsed"
- DNS egress should work for both `coredns` and `kube-dns` (via `k8s-app: kube-dns`)
- `prometheus` port and app labels might depend on deployment setup, drop lines from the strict default, or tune values as you see fit
- `opentelemetry-collector` values are the regular defaults from the [collector helm chart](https://github.com/open-telemetry/opentelemetry-helm-charts/blob/1d31c4bf71445595a3a7f5f2edc0850a83422a90/charts/opentelemetry-collector/values.yaml#L238-L285) - change as you see fit

Consider using the [Network Policy Editor](https://editor.networkpolicy.io/) for more interactive sanity.



--8<-- "includes/abbreviations.md"
--8<-- "includes/links.md"
