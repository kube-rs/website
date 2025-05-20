# Admission

This chapter talks about controlling admission through imperative or declarative validation:

- [admission controllers](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/) / admission controller frameworks
- [CRD validation with CEL](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/#validation-rules)
- [admission policies](https://kubernetes.io/docs/reference/access-authn-authz/validating-admission-policy/)

## Validation Using CEL Validation
CRDs (can be extended with validation rules written in [CEL](https://kubernetes.io/docs/reference/using-api/cel/), with canonical examples on [kubernetes.io crd validation-rules](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/#validation-rules).

```yaml
  openAPIV3Schema:
    type: object
    properties:
      spec:
        type: object
        x-kubernetes-validations:
          - rule: "self.minReplicas <= self.replicas"
            message: "replicas should be greater than or equal to minReplicas."
          - rule: "self.replicas <= self.maxReplicas"
            message: "replicas should be smaller than or equal to maxReplicas."
        properties:
          ...
          minReplicas:
            type: integer
          replicas:
            type: integer
          maxReplicas:
            type: integer
        required:
          - minReplicas
          - replicas
          - maxReplicas
```

If your controller [[object]] is a CRD you own, then this is the recommended way to include validation because it is much less error prone than writing an admission controller. The feature is GA on new clusters, but otherwise generally available as __Beta__ unless your [cluster is EOL](https://endoflife.date/kubernetes):

!!! note "Feature: CustomResourceValidationExpressions"

    This requires __Kubernetes >=1.25__ (where the feature is Beta), or Kubernetes >= 1.29 (where the [feature is GA](https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG/CHANGELOG-1.29.md)).


To include validation rules in the schemas you must add `x-kubernetes-validations` entries by [[schemas#overriding-members]] for the necessary types manually (or use the `x-kube` validation attribute). The manual way (which does not depend on `KubeSchema`):

```rust
fn string_legality(_: &mut schemars::gen::SchemaGenerator) -> schemars::schema::Schema {
    serde_json::from_value(serde_json::json!({
        "type": "string",
        "x-kubernetes-validations": [{
            "rule": "self != 'illegal'",
            "message": "string cannot be illegal"
        }]
    }))
    .unwrap()
}
```

this fn can be attached with a `#[schemars(schema_with = "string_legality)]` field attribute on some `Option<String>` (in this example). See [#1372](https://github.com/kube-rs/kube/pull/1372/files) too see interactions with errors and a larger struct and other validations.

## `x_kube` validation

To reduce manual schema overriding for CRDs, the alternate [KubeSchema] derive macro can be used instead of [JsonSchema].

!!! note "`JsonSchema` vs `KubeSchema`"

    This macro generates `schemars` `JsonSchema` derive macro for the provided structure. Keep in mind that using the `KubeSchema` derive macro replaces `JsonSchema` derive, and specifying both will cause a conflict.*


This implementation allows users to declaratively extend each field with validation rules (along with other `x-kubernetes` schema properties).

### `x_kube(validation = …)` attribute
This attribute can be used to set one or more `validation` rules on a field. Rules can be created via one of; an explicit [Rule] / a string expression / a (string, reason) string pair;

```rust
#[derive(KubeSchema)]
pub struct FooSpec {
    #[x_kube(
         validation = Rule::new("self != 'illegal'").message(Message::Expression("'string cannot be illegal'".into())).reason(Reason::FieldValueForbidden),
         validation = Rule::new("self != 'not legal'").reason(Reason::FieldValueInvalid),
         validation = "self == expected",
         validation = ("self == expected", "with error message"),
    )]
    cel_validated: String,
}
```

The `x_kube(validation = ...)` macro uses the [Rule] structure underneath. This can be constructed using the builder pattern, allowing users to extend the validation with a `message` to distinguish specific validation error and alternative [reasons](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/#field-reason) via `reason`, as well as a `field_path` for detailed json path to the invalid field value.

Alternatively, the rule can be constructed implicitly from a string or a tuple of two strings. The first string represents the validation rule, and the second string is the message assigned to the rule.

To write CEL expressions consider using the [CEL playground](https://playcel.undistro.io/). There are more examples in the [CRD Validation Rules announcement blog](https://kubernetes.io/blog/2022/09/23/crd-validation-rules-beta/) and under [kubernetes.io crd validation-rules](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/#validation-rules).

### `x_kube(merge_strategy = …)` attribute

This `x-kubernetes` extension flag controls the [Kubernetes SSA merge strategy](https://kubernetes.io/docs/reference/using-api/server-side-apply/#merge-strategy) from our [MergeStrategy] enum and facilitates the structuring of lists and maps in a specific format.

```rust
#[derive(KubeSchema)]
pub struct FooSpec {
    #[x_kube(merge_strategy = ListType::Map("key"))]
    merge: Vec<FooItem>,
}

pub struct FooItem {
    key: String,
    value: String,
}
```

This example generates a `x-kubernetes-list-type=map` and `x-kubernetes-list-map-keys=["key"]` attributes with the field. This instructs the API server to treat the underlying list as a map and ensures that `key` field is used as a unique key for the internal map, preventing conflicts on submission of duplicate keys by different managers.

## Validation Using Webhooks
AKA writing an [admission controller](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/).

These controllers __run as webservers__ rather than the traditional controller loop, and are given an [AdmissionReview] containing an [AdmissionRequest] that you must inspect and decide whether to [deny](https://docs.rs/kube/latest/kube/core/admission/struct.AdmissionResponse.html#method.deny) or accept.

An admission controller can be [Validating](https://docs.rs/k8s-openapi/latest/k8s_openapi/api/admissionregistration/v1/struct.ValidatingWebhook.html), [Mutating](https://docs.rs/k8s-openapi/latest/k8s_openapi/api/admissionregistration/v1/struct.MutatingWebhook.html) or both.

See the [kube::core::admission] module for how to set this up, or the [example mutating admission_controller using warp](https://github.com/kube-rs/kube/blob/main/examples/admission_controller.rs).

!!! warning "Admission controller management is hard"

    Creating an admission webhook requires a [non-trivial amount of certificate management](https://github.com/kube-rs/kube/blob/main/examples/admission_setup.sh) for the [webhookconfiguration](https://github.com/kube-rs/kube/blob/main/examples/admission_controller.yaml.tpl), and come with its fair share of footguns (see e.g. [Benefits and Dangers of Admission Controllers KubeCon'23](https://www.youtube.com/watch?v=6kK9otYAYac)).

    Consider CEL validation / CEL policies before writing an admission controllers.

Two examples of admission controllers in rust using kube:

- [kuberwarden-controller](https://github.com/kubewarden/kubewarden-controller)
- [linkerd-policy-controller](https://github.com/linkerd/linkerd2/tree/main/policy-controller)

## Validation Using Policies
External or native objects (that you do not wish to validate at the CRD level), can be validated externally using a `ValidatingAdmissionPolicy`.

These [AdmissionPolicies](https://kubernetes.io/docs/reference/access-authn-authz/validating-admission-policy/) let you inline CEL validation rules in an object similar to the WebhookConfiguration object for admission controllers, and tell Kubernetes to reject/accept for you based on simpler CEL expressions.

!!! note "Feature: ValidatingAdmissionPolicy"

    This feature is available in __Beta in 1.28__. The talk [Declarative Everything at KubeCon'23](https://www.youtube.com/watch?v=rFaWmd7Y7i0) shows the current status of the feature and its plans for mutation.


## Validation Using Frameworks
If your use-case is company-wide security policies, then rather than writing an admission controller, or waiting for `AdmissionPolicy` to handle your case, consider the currently available major tooling for admission policies:

- [Kyverno](https://kyverno.io/) - [policy list](https://kyverno.io/policies/)
- [Kubewarden](https://www.kubewarden.io/) - [oci installable policies](https://artifacthub.io/packages/search?kind=13&sort=relevance&page=1)
- [OPA Gatekeeper](https://open-policy-agent.github.io/gatekeeper/website/) - [regu policies](https://open-policy-agent.github.io/gatekeeper-library/website/)

If you are creating validation for a CRD on the other hand, then it's less ideal to tie the validation to a particular framework as this can limit adoption of your operator.

--8<-- "includes/abbreviations.md"
--8<-- "includes/links.md"
