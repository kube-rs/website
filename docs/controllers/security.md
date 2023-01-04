# Security

Best practices for creating secure, least-privilege controllers with kube.

## Problem Statement

When we are deploying a `Pod` into a cluster with **elevated controller credentials**, we are creating an **attractive escalation target** for attackers. Because of the numerous attack paths on pods and clusters that exists, we should be **extra vigilant** and following the [least-privilege principle](https://en.wikipedia.org/wiki/Principle_of_least_privilege).

While we can reap **some security benefits** from the Rust language itself (e.g. memory safety, race condition protection), this alone is insufficient.

### Potential Consequences of a Breach

If an attacker can compromise your pod, or in some other ways piggy-back on a controller's access, the consequences could be severe.

The incident scenarios usually vary based on **what access attackers acquire**:

- cluster wide secret access ⇒ secret oracle for attackers / data exfiltration
- cluster wide write access to common objects ⇒ denial of service attacks / exfiltration
- external access ⇒ access exfiltration
- pod creation access ⇒ bitcoin miner installation
- host/privileged access ⇒ secret data exfiltration/app installation

See [Trampoline Pods: Node to Admin PrivEsc Built Into Popular K8s Platorms](https://www.youtube.com/watch?v=PGsJ4QTlKlQ) as an example of how these types of attacks can work.

## Access Constriction

Depending on the scope of what your controller is in charge of, you should review and **constrict**:

| Access Scope | Access to review              |
| ------------ | ----------------------------- |
| Cluster Wide | `ClusterRole` rules           |
| Namespaced   | `Role` rules                  |
| External     | Token permissions / IAM roles |

### RBAC Access

Managing the RBAC rules requires a **declaration** somewhere (usually in your yaml/chart) of your controllers access **intentions**.

Kubernetes manifests with such rules can be kept up-to-date via [[testing#end-to-end-tests]] in terms of **sufficiency**, but one should also **document the intent** of your controller so that excessive permissions are not just "assumed to be needed" down the road.

!!! note ""

    RBAC generation from [Client] usage [has been proposed](https://github.com/kube-rs/kube/issues/1115).

### CRD Access
Installing a CRD into a cluster requires write access to `customresourcedefinitions`. This **can** be requested for the controller, but because this is such a heavy access requirement that is only really needed at the install/upgrade time, it is often **handled separately**. This also means that a controller often assumes the CRD is installed when running (and panicking if not).

If you do need CRD write access, consider **scoping** this to _non-delete_ access, and only for the `resourceNames` you expect:

```yaml
- apiVersion: rbac.authorization.k8s.io/v1
  kind: ClusterRole
  metadata:
    name: NAME
  rules:
  - apiGroups:
    - apiextensions.k8s.io
    resourceNames:
    - mycrd.kube.rs
    resources:
    - customresourcedefinitions
    verbs:
    - create
    - get
    - list
    - patch
```

### Role vs. ClusterRole
Use `Role` (access for a single namespace only) over `ClusterRole` unless absolutely necessary.

Some common access downgrade paths:

- if a controller is only working on an enumerable list of namespaces, create a `Role` with the access `rules`, and a `RoleBinding` for each namespace
- if a controller is always generating its dependent resources in a single namespace, you could expect the crd to also be installed in that same namespace.

### Namespace Separation

Deploy the controller to its own namespace to ensure leaked access tokens cannot be used on anything but the controller itself.

The **installation namespace** can also easily be separated from the **controlled namespace**.

### Container Permissions

Follow the [standard guidelines](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/) for securing your controller pods.
The following properties are recommended security context flags to constrain access:

- `runAsNonRoot: true` or `runAsUser`
- `allowPrivilegeEscalation: false`
- `readOnlyRootFilesystem: true`
- `capabilities.drop: ["ALL"]`

But they **might not be compatible** with your current container setup. See documentation of [Kubernetes Security Context Object](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.26/#podsecuritycontext-v1-core).

For cluster operators, the [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/) are also beneficial.

### Base Images

Minimizing the attack surface and amount extraneous code in your base image is also beneficial. It's worth **reconsidering** and finding alternatives for:

- :material-close: `ubuntu` or `debian` (out of date deps hitting security scanners)
- :material-close: `busybox` or `alpine` for your shell/debug access (escalation attack surface)
- :material-close: `scratch` (basically a blank default root user)

Instead, consider these security optimized base images:

- :material-check: [distroless base images](https://github.com/GoogleContainerTools/distroless#distroless-container-images) (e.g. [`:cc`](https://github.com/GoogleContainerTools/distroless/tree/main/cc) for glibc / [`:static`](https://github.com/GoogleContainerTools/distroless/tree/main/base) for musl)
- :material-check: [chainguard base images](https://github.com/chainguard-images/images#chainguard-images) (e.g. [gcc-glibc](https://github.com/chainguard-images/images/tree/main/images/gcc-glibc) or [static](https://github.com/chainguard-images/images/tree/main/images/static) for musl)

## Supply Chain Security

If malicious code gets injected into your controller through dependencies, you can still get breached even when following all the above.
Thankfully, you will also **most likely** hear about it quickly from your **security scanners**, so make sure to use one.

We recommend the following selection of tools that play well with the Rust ecosystem:

- [dependabot](https://github.blog/2020-06-01-keep-all-your-packages-up-to-date-with-dependabot/) or [renovate](https://github.com/renovatebot/renovate) for automatic dependency updates
- [`cargo audit`](https://github.com/rustsec/rustsec/blob/main/cargo-audit/README.md) against [rustsec](https://rustsec.org/)
- [`cargo deny`](https://embarkstudios.github.io/cargo-deny/)

## References

- [CNCF Operator WhitePaper](https://www.cncf.io/wp-content/uploads/2021/07/CNCF_Operator_WhitePaper.pdf)
- [Red Hat Blog: Kubernetes Operators: good security practices](https://www.redhat.com/en/blog/kubernetes-operators-good-security-practices)
- [CNL: Creating a “Paved Road” for Security in K8s Operators](https://www.youtube.com/watch?v=dyA2msK0pZE)
- [Kubernetes Philly, November 2021 - Distroless Docker Images](https://www.youtube.com/watch?v=1R6vjpVON1o)
- [Wolfi OS and Building Declarative Containers](https://www.youtube.com/watch?v=i4vE45c0fs8) (Chainguard)

--8<-- "includes/abbreviations.md"
--8<-- "includes/links.md"

[//begin]: # "Autogenerated link references for markdown compatibility"
[testing#end-to-end-tests]: testing "Testing"
[//end]: # "Autogenerated link references"
