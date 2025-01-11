# Schemas

The schema is a required part of a [CustomResource] because the apiserver only accepts a [CustomResourceDefinition] with a valid schema.

<!--
Basic [`#[kube]` attributes](https://docs.rs/kube/latest/kube/derive.CustomResource.html#optional-kube-attributes) will influence some aspects of the schema.
-->

There are [three main ways](https://docs.rs/kube/latest/kube/derive.CustomResource.html#kubeschema--mode) to get a schema injected into the [CustomResourceDefinition].

- **derived** -> [[#Deriving-JsonSchema]] (default)
- **manual** -> [[#Implementing-JsonSchema]]
- **disabled** -> [[#Disabling-Schemas]]


## Using JsonSchema

The [JsonSchema] proc macro from [schemars] is what gives a struct the ability to produce a schema. By default, a struct must `impl JsonSchema` to be able to derive `CustomResource`.

In both `derive` mode (default) and `manual` mode, [[kube-derive]] forces an `impl JsonSchema` requirement. This impl is then [used by kube-derive](https://github.com/kube-rs/kube/blob/823f4b8db3852e6bdd271e72c56b8c40d6f962a8/kube-derive/src/custom_resource.rs#L376-L383) with our own [conformance rewriter for structural schemas](https://docs.rs/kube/latest/kube/core/schema/struct.StructuralSchemaRewriter.html).

When using `JsonSchema`, your generated [CustomResourceDefinition] (via [CustomResourceExt]) will contain a schema.

### Deriving JsonSchema

The default setting uses `#[derive(JsonSchema)]`, and [[kube-derive]] will propagate this derive to the generated Kubernetes struct.

This requires `#[derive(CustomResource, JsonSchema)]` on the spec struct:

```rust
#[derive(CustomResource, Deserialize, Serialize, Clone, Debug, JsonSchema)]
#[kube(kind = "Document", group = "kube.rs", version = "v1", namespaced)]
pub struct DocumentSpec {
    pub title: String,
    pub hide: bool,
    pub content: String,
}
```

This example (simplified variant from [controller-rs](https://github.com/kube-rs/controller-rs/blob/main/src/controller.rs)) generates a [CustomResourceDefinition] whose yaml representation (including schema) can be serialized using `serde_yaml::to_string(&Document::crd())?` and will output:

```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: documents.kube.rs
spec:
  group: kube.rs
  names:
    categories: []
    kind: Document
    plural: documents
    shortNames: []
    singular: document
  scope: Namespaced
  versions:
  - additionalPrinterColumns: []
    name: v1
    schema:
      openAPIV3Schema:
        description: Auto-generated derived type for DocumentSpec via `CustomResource`
        properties:
          spec:
            properties:
              content:
                type: string
              hide:
                type: boolean
              title:
                type: string
            required:
            - content
            - hide
            - title
            type: object
        required:
        - spec
        title: Document
        type: object
    served: true
    storage: true
    subresources: {}
```

See [[object#installation]] for a common pattern for generating this.

!!! note "Schema requirements are transitive"

    If your spec struct tries to derive `JsonSchema`, then all its members must also derive `JsonSchema`.

See [examples/crd_derive_schema](https://github.com/kube-rs/kube/blob/main/examples/crd_derive_schema.rs).

### Implementing JsonSchema

When using `#[kube(schema = "manual")]`, [[kube-derive]] will not insert the derive attr of `JsonSchema` on the generated struct, and you are expected to provide an `impl JsonSchema for GeneratedStruct` yourself.

This allows filling the gaps if your struct members only has partial `JsonSchema` coverage.

See [examples/crd_derive_custom_schema](https://github.com/kube-rs/kube/blob/823f4b8db3852e6bdd271e72c56b8c40d6f962a8/examples/crd_derive_custom_schema.rs#L22-L56).

### Overriding Members

When you are implementing or deriving `JsonSchema`, you can override specific parts of a `JsonSchema` schema using [`#[schemars(schema_with)]`](https://graham.cool/schemars/examples/7-custom_serialization/). Some specific examples:

- [overriding merge strategy on a vec](https://github.com/kube-rs/kube/blob/823f4b8db3852e6bdd271e72c56b8c40d6f962a8/examples/crd_derive_schema.rs#L85-L102)
- [overriding x-kubernetes properties on a condition](https://github.com/kube-rs/kube/blob/823f4b8db3852e6bdd271e72c56b8c40d6f962a8/examples/crd_derive.rs#L60-L85)


## Disabling Schemas

When using `#[kube(schema = "disabled)]`, you are telling [[kube-derive]] not to use [schemars] at all, and you are taking responsibility for creating the schema manually. This removes all the safety mechanisms, and requires manually patching the schema fields, and dealing with structural schema quirks yourself.

!!! warning "Disabling schemas invalidates the generated CRD"

    Setting this option means the [CustomResourceDefinition] provided by [CustomResourceExt] will require modification.

Any manual schemas must be attached to the generated [CustomResourceDefinition] before use. An example of this can be found in [examples/crd_derive_no_schema](https://github.com/kube-rs/kube/blob/main/examples/crd_derive_no_schema.rs).

The main reason for going down this approach is if you are porting a controller with a CRD from another language and you want 100% conformance to the existing schema out of the gate.

This method allows eliding the `#[derive(JsonSchema)]` instruction, and possibly also `schemars` from the dependency tree if you are careful with features.


## Versioning
It is possible to progress between two structs deriving `CustomResource` in a versioned manner.

You can define multiple structs within versioned modules ala https://github.com/kube-rs/kube/blob/main/examples/crd_derive_multi.rs and then use [merge_crds] to combine them.

See [CustomResource#versioning](https://docs.rs/kube/latest/kube/derive.CustomResource.html#versioning), and upstream docs on [Versions in CustomResourceDefinitions](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definition-versioning/) for more info.

## Validation
Kubernetes >1.25 supports including [validation rules in the openapi schema](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/#validation-rules), and there are a couple of ways to include these. See [[admission#Validation Using CEL Validation]] for examples.

### Manual Rules
This can be done by following upstream docs, and manually [[#Implementing-JsonSchema]] or [[#Overriding-Members]] to inject validation rules into specific parts of the schema.

This approach will let you use the [1.25 Common Expression Language feature](https://kubernetes.io/blog/2022/09/23/crd-validation-rules-beta/).
There are currently no recommended ways of doing client-side validation with this approach, but there are new [cel parser/interpreter crates](https://crates.io/search?q=cel) and a [cel expression playground](https://playcel.undistro.io/) that might be useful here.

### Deriving via Garde
Using [garde] is nice for the simple case because it allows doing both client-side validation, and server-side validation, with the caveat that it only works on both sides for **basic validation rules** as [schemars can only pick up on some of them](https://graham.cool/schemars/deriving/attributes/#supported-validator-attributes).

See [CustomResource#schema-validation](https://docs.rs/kube/latest/kube/derive.CustomResource.html#schema-validation).


--8<-- "includes/abbreviations.md"
--8<-- "includes/links.md"



[//begin]: # "Autogenerated link references for markdown compatibility"
[#overriding]: schemas "Schemas"
[//end]: # "Autogenerated link references"
