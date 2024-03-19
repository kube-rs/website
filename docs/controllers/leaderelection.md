# Leader Election

This chapter is a stub about Leases, Leader Election and how to achieve distributed locks around Kubernetes resources.

!!! note "Terminology"

    See [Kubernetes//Leases](https://kubernetes.io/docs/concepts/architecture/leases/) for introductory definitions.


## Crates

At the moment, leader election support is not supported by `kube` itself, and requires 3rd party crates (see [kube#485](https://github.com/kube-rs/kube/issues/485#issuecomment-1837386565)).

### kube-leader-election
The [`kube-leader-election` crate](https://crates.io/crates/kube-leader-election/) via [hendrikmaus/kube-leader-election](https://github.com/hendrikmaus/kube-leader-election) implements a simple and low-level form of leader election with a [use-case disclaimer](https://github.com/hendrikmaus/kube-leader-election?tab=readme-ov-file#kubernetes-lease-locking).

```rust
use kube_leader_election::{LeaseLock, LeaseLockParams};
let leadership = LeaseLock::new(client, namespace, LeaseLockParams { ... });
let _lease = leadership.try_acquire_or_renew().await?;
leadership.step_down().await?;
```

It has [simple examples](https://github.com/hendrikmaus/kube-leader-election/tree/master/examples), documented at [docs.rs/kube-leader-election](https://docs.rs/kube-leader-election/)

### kube-coordinate
The [`kube-coordinate` crate](https://crates.io/crates/kube-coordinate) via [thedodd/kube-coordinate](https://github.com/thedodd/kube-coordinate) is a newer crate that implements a high-level and sophisticated form of leader election with a passable handle to gate actions on.

```rust
use kube_coordinate::{LeaderElector, Config};
let handle = LeaderElector::spawn(Config {...}, client);
let state_chan = handle.state();
if state_chan.borrow().is_leader() {
    // Only perform leader actions if in leader state.
}
```

It is documented at [docs.rs/kube-coordinate](https://docs.rs/kube-coordinate/).

### kubert
The [`kubert` crate](https://github.com/olix0r/kubert) via [olix0r/kubert](https://github.com/olix0r/kubert) is linkerd's utility crate. It contains a low-level `lease` module.

```rust
use kubert::lease::{ClaimParams, LeaseManager};
let lease_api: Api<Lease> = Api::namespaced(client, namespace);
let lease = LeaseManager::init(lease_api, name).await?;
let claim = lease.ensure_claimed(&identity, &ClaimParams { ... }).await?;
assert!(claim.is_current_for(&identity));
```

It is documented at [docs.rs/kubert/lease](https://docs.rs/kubert/latest/kubert/lease/index.html), has a [large lease example](https://github.com/olix0r/kubert/blob/main/examples/lease.rs), and used by [linkerd's policy-controller](https://github.com/linkerd/linkerd2/blob/1f4f4d417c6d06c3bd5a372fc75064f967117886/policy-controller/src/main.rs).


<!-- OTHER ALTERNATIVES???
Know other alternatives? Feel free to raise a PR here with a new H3 entry.

Try to follow roughly the short and (ideally) minimally subjective format above.
-->


--8<-- "includes/abbreviations.md"
--8<-- "includes/links.md"
