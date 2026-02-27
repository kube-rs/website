# Server-Side Apply

[Server-Side Apply] is a Kubernetes patch strategy based on field ownership. It allows multiple controllers to safely modify the same resource by tracking which controller owns which fields.

This page covers practical patterns, common pitfalls, and status patching with SSA in kube.

!!! note "SSA and Reconciler Idempotency"

    SSA naturally fits the [[reconciler]]'s idempotent pattern: you declare "these fields should have these values", and the server handles the rest. See [[reconciler#in-depth-solution]] for how SSA simplifies reconciler logic.

## Why SSA

The traditional patch strategies each have limitations:

| Strategy | Limitation |
|----------|-----------|
| Merge patch | Overwrites entire arrays. Field deletion is not explicit |
| Strategic merge patch | Only works with k8s-openapi types. Incomplete for CRDs |
| JSON patch | Requires exact paths. Susceptible to race conditions |

SSA addresses these:

- **Field ownership**: the server records "this controller owns this field"
- **Conflict detection**: touching another owner's field produces a `409 Conflict`
- **Declarative**: you declare which fields should have which values; everything else is left untouched

## Basic Pattern

```rust
use kube::api::{Patch, PatchParams};

let patch = Patch::Apply(serde_json::json!({
    "apiVersion": "v1",
    "kind": "ConfigMap",
    "metadata": { "name": "my-cm" },
    "data": { "key": "value" }
}));
let pp = PatchParams::apply("my-controller"); // field manager name
api.patch("my-cm", &pp, &patch).await?;
```

The `"my-controller"` string in `PatchParams::apply` is the **field manager** name. Ownership is tracked under this name. Applying again with the same field manager updates owned fields; fields owned by other managers are left alone.

## Common Pitfalls

### Missing apiVersion and kind

```rust
// ✗ 400 Bad Request
let patch = Patch::Apply(serde_json::json!({
    "data": { "key": "value" }
}));

// ✓ apiVersion and kind are required
let patch = Patch::Apply(serde_json::json!({
    "apiVersion": "v1",
    "kind": "ConfigMap",
    "metadata": { "name": "my-cm" },
    "data": { "key": "value" }
}));
```

Unlike merge patch, SSA requires `apiVersion` and `kind` in every request.

### Missing field manager

```rust
// ✗ field_manager is None → API server rejects the request
let pp = PatchParams::default();

// ✓ Explicit field manager
let pp = PatchParams::apply("my-controller");
```

A field manager is **required** for SSA. When `field_manager` is `None` (the default), the API server returns an error. Always use `PatchParams::apply("my-controller")` for SSA operations.

### Overusing force

```rust
// Caution: forcibly takes ownership of fields from other managers
let pp = PatchParams::apply("my-controller").force();
```

`force: true` takes ownership of fields from other controllers. Only use this in single-owner situations such as CRD registration.

### Including unnecessary fields

Serializing an entire Rust struct includes `Default` value fields. SSA takes ownership of those fields, causing conflicts when another controller tries to modify them.

```rust
// ✗ Serializes all Default fields → unnecessary ownership
let full_deployment = Deployment { ..Default::default() };

// ✓ Only include fields you actually manage
let patch = serde_json::json!({
    "apiVersion": "apps/v1",
    "kind": "Deployment",
    "metadata": { "name": "my-deploy" },
    "spec": {
        "replicas": 3
    }
});
```

!!! note "Current limitation: no ApplyConfigurations in Rust"

    Go's client-go provides [ApplyConfigurations](https://pkg.go.dev/k8s.io/client-go/applyconfigurations) - fully optional builder types designed specifically for SSA. Rust does not have an equivalent yet ([kube#649](https://github.com/kube-rs/kube/issues/649)). Some [k8s-openapi] fields are not fully optional (e.g. certain integer fields like `maxReplicas`), which can make typed partial SSA awkward. Using `serde_json::json!()` for partial patches works around this issue.

## Status Patching

Status is modified through the `/status` subresource:

```rust
let status_patch = serde_json::json!({
    "apiVersion": "example.com/v1",
    "kind": "MyResource",
    "status": {
        "phase": "Ready",
        "conditions": [{
            "type": "Available",
            "status": "True",
            "lastTransitionTime": "2024-01-01T00:00:00Z",
        }]
    }
});
let pp = PatchParams::apply("my-controller");
api.patch_status("name", &pp, &Patch::Apply(status_patch)).await?;
```

!!! warning "Wrap status in the full object structure"

    ```rust
    // ✗ Sending just the status fields will fail
    serde_json::json!({ "phase": "Ready" })

    // ✓ Must include apiVersion, kind, and wrap under "status"
    serde_json::json!({
        "apiVersion": "example.com/v1",
        "kind": "MyResource",
        "status": { "phase": "Ready" }
    })
    ```

    The Kubernetes API expects the full object structure even on the `/status` endpoint.

## Typed SSA

Instead of `serde_json::json!()`, you can use Rust types for type safety and IDE autocompletion:

```rust
let cm = ConfigMap {
    metadata: ObjectMeta {
        name: Some("my-cm".into()),
        ..Default::default()
    },
    data: Some(BTreeMap::from([("key".into(), "value".into())])),
    ..Default::default()
};
let pp = PatchParams::apply("my-controller");
api.patch("my-cm", &pp, &Patch::Apply(cm)).await?;
```

[k8s-openapi] types already have `#[serde(skip_serializing_if = "Option::is_none")]` applied, so `None` fields are omitted from serialization. For your own types, you need to add this explicitly:

```rust
#[derive(Serialize)]
struct MyStatus {
    phase: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    message: Option<String>,
}
```

Without `skip_serializing_if`, `None` fields serialize as `null` and SSA takes ownership of them.

--8<-- "includes/abbreviations.md"
--8<-- "includes/links.md"

[//begin]: # "Autogenerated link references for markdown compatibility"
[reconciler]: reconciler "The Reconciler"
[//end]: # "Autogenerated link references"
