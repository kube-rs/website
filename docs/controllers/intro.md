# Introduction

This chapter contains information on how to build controllers with kube-rs.

A controller consist of three pieces:

- an object dictating what the world should see (the **spec**)
- an application running inside kubernetes watching the spec and related objects (the **application**)
- an idempotent function that ensures the state of one object is applied to the world (the **reconciler**)

In short:

> A controller a long-running program that ensures the kubernetes state of an object, matches the state of the world.

It ensures this by watching the object, and reconciling any differences when they occur.

## The Specification

The main object is the specification for what the world should be like, and it takes the form of one or more Kubernetes objects, like say a:

- [Pod](https://arnavion.github.io/k8s-openapi/v0.14.x/k8s_openapi/api/core/v1/struct.Pod.html)
- [Deployment](https://arnavion.github.io/k8s-openapi/v0.14.x/k8s_openapi/api/apps/v1/struct.Deployment.html)
- ..[any native Kubernetes Resource](https://arnavion.github.io/k8s-openapi/v0.14.x/k8s_openapi/trait.Resource.html#implementors)
- a dynamic object from [api discovery](https://docs.rs/kube/latest/kube/discovery/index.html)
- a [Custom Resource](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/)

Because Kubernetes already a [core controller manager](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-controller-manager/) for the core native objects, the most common use-case is Custom Resources, but the process outlined herein system works equally well for all resources.

The object(s) we are interested in [typically contains a Spec](https://kubernetes.io/docs/concepts/overview/working-with-objects/kubernetes-objects/#object-spec-and-status) (or something equivalent) which describe the **desired state of the world** and we will use this term to refer to our main object(s) in a controller.

## The Application

The job of the controller application is simply to watch the core object(s), and any related objects for changes, and then relay the information to the reconciler.

The application, as far as this guide is concerned, takes the form of a **rust application** using the `kube` crate as a **dependency** with the `runtime` feature, compiled into a **container**, and deployed in kubernetes as a **`Deployment`**.

The core components inside the application are:

- infinite [watch loops](https://kubernetes.io/docs/reference/using-api/api-concepts/#efficient-detection-of-changes) around relevant objects
- a system that maps object changes to the relevant specification
- one or more **idempotent reconcilers** acting on a single object

And because of Kubernetes constraints; the system must be **fault-tolerant**. It must be able to recover from **crashes**, **downtime**, and resuming even having **missed messages**.

Setting up a blank controller in rust is fairly simply, can be done with minimal boilerplate (no generated files need be inlined in your project), and will be covered in TODO: APPLICATIONDOC.

The hard part of writing a controller lies in the business logic: the reconciler.

## The Reconciler

In its simplest form, this is what a noop reconciler (a reconciler that does nothing) looks like:

```rust
async fn reconcile(object: Arc<MyObject>, data: Context<Data>) -> Result<ReconcilerAction, Error> {
    Ok(ReconcilerAction {
        requeue_after: Some(Duration::from_secs(3600 / 2)),
    })
}
```

// TODO: does the requeue mechanism take the first or the last? it should take the last..
// TODO: ReconcilerAction::default ? why is it not an enum again?

It takes the last seen version of your `object`, passes it to a user-defined function along with some user `data`, and then performs actions to align the world with `object`.

In practice the reconciler, is the warmest user-defined code in your controller, and it will end up doing a range of tasks including:

- extracting a `Client` or an `Api` from the `Data`
- performing mutating api calls to:
  * your `object`'s **child resources** / related resources
  * the `object`'s **status struct** for other api consumers of the object
  * the `Event` api for diagnostic information
- managing annotations for [ownership](https://kubernetes.io/docs/concepts/overview/working-with-objects/owners-dependents/) or [garbage collection](https://kubernetes.io/docs/concepts/overview/working-with-objects/finalizers/) within kubernetes
- handling instrumentation for tracing, logs and metrics

..and to make matters more confusing, sometimes controllers sit in front of the watch machinery and is in charge of [admission into Kubernetes](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/).

We will go through all these details herein and you can compose the various techniques as you see fit depending on your use case.
