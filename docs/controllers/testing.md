# Testing

This chapter covers **controller testing** and example Rust Kubernetes test patterns.
## Terminology

We will loosely re-use the [kube test categories](https://github.com/kube-rs/kube/blob/main/CONTRIBUTING.md#testing) and outline four types of tests:

- **End to End tests** (requires Kubernetes through an **in-cluster** Client)
- **Integration tests** (requires Kubernetes)
- **Mocked unit tests** (requires mocking Kubernetes dependencies)
- **Unit tests** (no Kubernetes calls)

These types should roughly match what you see in a standard __test pyramid__ where testing power and maintenance costs both increase as you go up the list.

!!! note "Classification Subjectivity"

    This classification and terminology re-use herein is partially subjective. Variant approaches are discussed.
## Unit Tests

The basic unit `#[test]`. Typically composed of individual test function in a __tests only__ module inlined in files containing what you want to test.

We will defer to various official guides on good unit test writing in rust:

- [rust by example - unit tests](https://doc.rust-lang.org/rust-by-example/testing/unit_testing.html)
- [rust book - writing tests](https://doc.rust-lang.org/book/ch11-01-writing-tests.html)

### Benefits

Very simple to setup, with generally no extra interfaces needed.

Works extremely well for algorithms, state machinery, and business logic that has been separated out from network behavior (e.g. the [sans-IO](https://sans-io.readthedocs.io/) approach). Splitting out business logic from IO will reduce the need for more expensive tests below and should be favored where possible.

### Downsides

While it is definitely possible to [go overboard with unit tests](https://verraes.net/2014/12/how-much-testing-is-too-much/) and test too deeply (without protecting any real invariants), this is not what we will focus on here. When unit tests are appropriate, they are great.

In the controller context, the **main unit test downside** is that we **cannot cover the IO component** without something standing in for Kubernetes - such as an apiserver mock or an actual cluster - making it, by definition, not a plain unit test anymore. 

The controller is fundamentally tied up in the [[reconciler]], so there is always going to be a sizable chunk of code that you **cannot do with plain unit tests**.

## Kubernetes IO Strategies
For the [[reconciler]] (and similar Kubernetes calling logic you may have), there are **3 major strategies to test** this code.

You have one basic choice:

1. stay in unit-test land by mocking out your network dependencies (worse test code)
2. move up the test pyramid and do full-scale integration testing (worse test reliability)

and then you can also choose to do e2e testing either as an additional bonus, or as a substitute for integration testing. Larger projects **may wish to do everything**.

!!! note "Idempotency reducing the need for tests"

    The more you learn to lean on using [Server-Side Apply], the less if/else gates will end up with in your reconciler, and thus the less testing you will need.

## Unit Tests with Mocks

It is possible to to test your reconciler and IO logic and retain the speed and isolation of unit tests by using mocks. This is common practice to avoid having to bring in your all your dependencies and is typically done through crates such as [wiremock](https://crates.io/crates/wiremock), [mockito](https://crates.io/crates/mockito), [tower-test](https://crates.io/crates/tower-test), or [mockall](https://crates.io/crates/mockall).

Out of these, [tower-test](https://crates.io/crates/tower-test) integrates well with our [Client] out of the box, and is the one we will focus on here.

<!-- TODO: links to other use cases with wiremock? -->

### Example
To create a mocked [Client] with `tower-test` it is sufficient to instantiate one on a mock service:

```rust
let (mocksvc, handle) = tower_test::mock::pair::<Request<Body>, Response<Body>>();
let client = Client::new(mocksvc, "default");
```

This is using the generic:

- [`http::Request`](https://docs.rs/http/latest/http/request/struct.Request.html) + [`http::Response`](https://docs.rs/http/latest/http/response/struct.Response.html) objects
- [`hyper::Body`](https://docs.rs/hyper/latest/hyper/struct.Body.html) as request/response content

This `Client` can then be passed into to reconciler in the usual way through a context object ([[reconciler##using-context]]), allowing you to test `reconcile` directly.

You do need to write a bit of code to make the test `handle` do the right thing though, and this does require a bit of boilerplate because there is nothing equivalent to [`envtest`](https://book.kubebuilder.io/reference/envtest.html) in Rust ([so far](https://github.com/kube-rs/kube/issues/1108)). Effectively, we need to mock bits of the [kube-apiserver](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-apiserver/) and it can look something like this:

```rust
// We wrap tower_test::mock::Handle
type ApiServerHandle = tower_test::mock::Handle<Request<Body>, Response<Body>>;
pub struct ApiServerVerifier(ApiServerHandle);

/// Scenarios we want to test for
pub enum Scenario {
    /// We expect exactly one `patch_status` call to the `Document` resource
    StatusPatch(Document),
    /// We expect nothing to be sent to Kubernetes
    RadioSilence,
}
impl ApiServerVerifier {
    pub fn run(self, scenario: Scenario) -> tokio::task::JoinHandle<()> {
        tokio::spawn(async move { // moving self => one scenario per test
            match scenario {
                Scenario::StatusPatch(doc) => self.handle_status_patch(doc).await,
                Scenario::RadioSilence => Ok(self),
            }
            .expect("scenario completed without errors");
        })
    }
    
    /// Respond to PATCH /status with passed doc + status from request body
    async fn handle_status_patch(mut self, doc: Document) -> Result<Self> {
        let (request, send) = self.0.next_request().await.expect("service not called");
        assert_eq!(request.method(), http::Method::PATCH);
        let exp_url = format!("/apis/kube.rs/v1/namespaces/testns/documents/{}/status?&force=true&fieldManager=cntrlr", doc.name_any());
        assert_eq!(request.uri().to_string(), exp_url);
        // extract the `status` object from the `patch_status` call via the body of the request
        let req_body = to_bytes(request.into_body()).await.unwrap();
        let json: serde_json::Value = serde_json::from_slice(&req_body).expect("patch_status object is json");
        let status_json = json.get("status").expect("status object").clone();
        let status: DocumentStatus = serde_json::from_value(status_json).expect("contains valid status");
        // attach it to the supplied document to pretend we are an apiserver
        let response = serde_json::to_vec(&doc.with_status(status)).unwrap();
        send.send_response(Response::builder().body(Body::from(response)).unwrap());
        Ok(self)
    }
}
```

Here we have made an apiserver mock wrapper that will run certain scenarios. Each scenario calls a number of handler functions that assert on certain basic expectations about the nature of the message we receive. Here we only have made one for `handle_status_patch`, but more are used in [controller-rs/fixtures.rs](https://github.com/kube-rs/controller-rs/blob/main/src/fixtures.rs).

An **actual tests** that uses the above wrapper can end up being quite readable:

```rust
#[tokio::test]
async fn doc_reconcile_causes_status_patch() {
    let (testctx, fakeserver) = Context::test();
    let doc = Document::test();
    let mocksrv = fakeserver.run(Scenario::StatusPatch(doc.clone()));
    reconcile(Arc::new(doc), testctx).await.expect("reconciler");
    timeout_after_1s(mocksrv).await;
}
```

Effectively, this is an exercise in running two futures together (one in a task), and one in the main test fn, then joining at the end.

In this test we are effectively **verifying** that:

1. reconcile ran successfully in the given scenario
2. apiserver handler saw all expected messages
3. apiserver handler saw no unexpected messages.

This is **satisfied because**:

1. reconcile is unwrapped while handler is running through the scenario
2. Each scenario blocked on sequential api calls to happen (we await each message), so mockserver's joinhandle will not resolve until **every** expected message in the given scenario has happened (hence the timeout) 
3. If the mock server is receiving more Kubernetes calls than expected the reconciler will error with a `KubeError(Service(Closed(())))` caught by the reconcilers `expect`

!!! note "Context and Document constructors omitted"

    Test functions to create the rest of the reconciler context and a test document used by a reconciler are not shown, see [controller-rs/fixtures.rs](https://github.com/kube-rs/controller-rs/blob/main/src/fixtures.rs) for a relatively small `Context`. Note that the more things you pass in to your reconciler the larger your `Context` will be, and the more stuff you will want to mock. 

### Benefits
Using mocks are __comparable__ to using integration tests in **power and versatility**. It lets us move up the pyramid in terms of testing power, but without needing an actual network boundary and a real cluster. As a result, we **maintain test reliability**.

### Downsides
Compared to using a real cluster, the amount of code we need to write - to compensate for a missing apiserver - is currently quite significant. This **verbosity** means a _higher initial cost_ of writing these tests, and also **more complexity** to keep in your head and maintain. We hope that some of this complexity can be reduced in the future with more [Kubernetes focused test helpers](https://github.com/kube-rs/kube/issues/1108).

### External Examples

- [nais/hahaha exec tests](https://github.com/nais/hahaha/blob/43cff519ffbc7c0106ff46f963c3308329301500/src/reconciler.rs#L205-L308) using [an automock trait](https://github.com/nais/hahaha/blob/43cff519ffbc7c0106ff46f963c3308329301500/src/api.rs#L13-L21)

## Integration Tests

Integration tests run against a **real Kubernetes cluster**, and lets you verify that the IO components of your controller is doing the right thing in a real environment. The big selling point is that they require little code to write and are easy to understand.

### Example
Let us try to verify the same status patching scenario from above using an integration test.

First, we need a working [Client]. Using `Client::try_default()` inside an async-aware `#[test]` we end up using using the `current-context` set in your local [kubeconfig](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/).

```rust
    // Integration test without mocks
    use kube::api::{Api, Client, ListParams, Patch, PatchParams};
    #[tokio::test]
    #[ignore = "uses k8s current-context"]
    async fn integration_reconcile_should_set_status() {
        let client = Client::try_default().await.unwrap();
        let ctx = State::default().to_context(client.clone());

        // create a test doc and run it through ~= kubectl apply --server-side
        let doc = Document::test().finalized().needs_hide();
        let docs: Api<Document> = Api::namespaced(client.clone(), "default");
        let ssapply = PatchParams::apply("ctrltest");
        let patch = Patch::Apply(doc.clone());
        docs.patch("test", &ssapply, &patch).await.unwrap();

        // reconcile it (as if it was applied to the cluster like this)
        reconcile(Arc::new(doc), ctx).await.unwrap();

        // verify side-effects happened
        let output = docs.get_status("test").await.unwrap();
        assert!(output.status.is_some());
    }
```

this sets up a `Client`, a `Context` (to be passed to the reconciler), then applies an actual document into the cluster, and at the same time giving it to the reconciler.

Feeding the apply result (usually seen by watching the api) is what the [Controller] internals does, so we skip testing this part. As a result, we get a much simpler test call around only `reconcile` that we can verify by querying the api after it has completed.

!!! note ""
    
    The tests at the bottom of [controller-rs/controller.rs](https://github.com/kube-rs/controller-rs/blob/f084c15985b5de1b2cfee627613cd2b69c9530cd/src/controller.rs#L281-L315) go a little deeper, testing a larger scenario.


We **need** a cluster for these tests though, so on CI we will spin up a [k3d] instance for each PR. Here is a GitHub Actions based setup:

```yaml
  integration:
    runs-on: ubuntu-latest
    strategy:
      # Prevent GitHub from cancelling all in-progress jobs when a matrix job fails.
      fail-fast: false
      matrix:
        # Run these tests against older clusters as well
        k8s: [v1.22, latest]
    steps:
      - uses: actions/checkout@v2
      - uses: actions-rs/toolchain@v1
        with:
          override: true
          toolchain: stable
          profile: minimal
      # Smart caching for Rust
      - uses: Swatinem/rust-cache@v2
      - uses: nolar/setup-k3d-k3s@v1
        with:
          version: ${{matrix.k8s}}
          k3d-name: kube
          # Used to avoid rate limits when fetching the releases from k3s repo.
          # Anonymous access is limited to 60 requests / hour / worker
          # github-token: ${{ secrets.GITHUB_TOKEN }}
          k3d-args: "--no-lb --no-rollback --k3s-arg --disable=traefik,servicelb,metrics-server@server:*"

      # Real CI work starts here
      - name: Build workspace
        run: cargo build

      # Run the integration tests
      - name: install crd
        run: cargo run --bin crdgen | kubectl apply -f -
      - name: Run all default features integration library tests
        run: cargo test --lib --all -- --ignored
```

This creates a minimal k3d cluster (against **both** the latest k3d version and **our** last supported k8s version), and then runs `cargo test -- --ignored` to specifically **only** run the `#[ignore]` marked integration tests.

!!! note "`#[ignore]` annotations on integration tests"

    We advocate for using the `#[ignore]` attribute as a visible opt-in for developers. The `Client::try_default` will work against whatever arbitrary cluster a developer has set to their `current-context`, so makes it harder (than merely typing `cargo test`) to accidentally modify random clusters.

### Benefits

As you can see, this is a lot simpler than the mocking version on the Rust side; no request/response handling and task spawning.

At the same time, these tests are more powerful than mocks; we can test the major flow path of a controller in a cluster against different Kubernetes versions with very little code.

### Downsides

#### Low Reliability

While this will vary between CI providers, cluster setup problems are common.

As you now depend on both cluster specific actions to set up a cluster (e.g. [setup-k3d-k3s](https://github.com/nolar/setup-k3d-k3s)), and the underlying cluster interface (e.g. [k3d]), you have to deal with compatibility issues between these. Spurious cluster creation failures on GHA are common (particularly on `latest`).

You also have to wait for resources to be ready. Usually, this involves waiting for a [Condition](https://docs.rs/kube/latest/kube/runtime/wait/trait.Condition.html), but Kubernetes does not have conditions for everything[*](https://docs.rs/kube/latest/kube/runtime/wait/conditions/fn.is_crd_established.html), so you can still run into race conditions.

It is **possible to reduce the reliability problems** a bit by using **dedicated clusters**, but that brings us onto the second pain point;

#### No Isolation
Tests from one file can cause **interactions and race conditions** with other tests, and re-using a cluster across test runs makes this problem worse as tests now need to be idempotent.

It is **possible** to achieve full test isolation for integration tests, but it often brings impractical costs (such as setting up a new cluster per test, or writing all tests to be idempotent and using disjoint resources).

Thus, you can only (realistically) write so many of these tests because you have to keep in your head which tests is doing what to your environment and they may be competing for the same resource names.

### Black Box Variant

The setup above is not a [black-box integration test](https://en.wikipedia.org/wiki/Black-box_testing), because we pull out internals to create state, and call `reconcile` almost like a unit test.

!!! note "Rust conventions on integration tests"

    [Rust defines integration tests](https://doc.rust-lang.org/book/ch11-03-test-organization.html) as acting only on public interfaces and residing in a separate `tests` directory. 

We effectively have a [white-box integration test](https://en.wikipedia.org/wiki/White-box_testing) instead.

It is **possible to export** our `reconcile` plus associated `Context` types as a new public interface from a new controller library, and then black-box test that (per the Rust definition) from a separate `tests` directory.

In the most basic cases, this is effectively a **definitional hack** as we;

- introduce an arbitrary public boundary that's only used by tests and controller main
- declare this boundary as public, and test that (in the exact same way)
- re-plumb controller main to use this interface rather than the old private internals

But this does also **separate the code** that we consider **important enough to test** from the rest, and that boundary has been **made explicit** via the (technically unnecessary) library (at the cost of having more files and boundaries).

Doing so will make make your interfaces more explicit, and this can be valuable for more advanced controllers using multiple reconcilers.

<!-- PRs welcome for examples -->

### Functional Variant

Rather than moving interfaces around to fit definitions of black-box tests, we can can also **remove all our assumptions about code layout** in the first place, and create more [functional tests](https://en.wikipedia.org/wiki/Functional_testing).

In functional tests, we instead **run the controller directly**, and test against it, via something like:

1. explicitly `cargo run &` the controller binary
2. `kubectl apply` a test document
3. verify your conditions outside (e.g. `kubectl wait` or a separate test suite)

[CoreDB's operator follows this approach](https://github.com/CoreDB-io/coredb/tree/main/coredb-operator/tests), and it is definitely an important thing to test. In this guide, you can see functional testing done as part of __End to End Tests__.
## End to End Tests

End to End tests install your release unit (image + yaml) into a cluster, then runs verification against the cluster and the application.

The most common use-case of this type of test is [smoke testing](https://en.wikipedia.org/wiki/Smoke_testing_(software)), but we **can** also test a multitude of integration scenarios using this approach.

### Example
We will do e2e testing to get a **basic verification** of our:

- **packaging system** (does the image work and install with the yaml pipeline?)
- **controller happy path** (does it reconcile on cluster mutation?)

This thus focuses entirely on the extreme **high-level details**, leaving lower-level specifics to integration tests, mocked unit tests, or even linting tools (for yaml verification).

As a result, we do not require any additional Rust code, as here we will treat the controller as a black box, and do all verification with `kubectl`.

!!! note "E2E Container Building"

    An e2e test will require access to the built container image, so spending time on CI caching can be helpful.

<!-- TODO: link to container doc-->

An example setup for GitHub Actions:

```yaml
  e2e:
    runs-on: ubuntu-latest
    needs: [docker]
    steps:
      - uses: actions/checkout@v2
      - uses: nolar/setup-k3d-k3s@v1
        with:
          version: v1.25
          k3d-name: kube
          k3d-args: "--no-lb --no-rollback --k3s-arg --disable=traefik,servicelb,metrics-server@server:*"
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v2
      - name: Download docker image artifact from docker job
        uses: actions/download-artifact@v3
        with:
          name: controller-image
          path: /tmp
      - name: Load docker image from tarball
        run: docker load --input /tmp/image.tar
      # install crd + controller (via chart)
      - run: kubectl apply -f yaml/crd.yaml
      - run: helm template charts/doc-controller | kubectl apply -f -
      - run: kubectl wait --for=condition=available deploy/doc-controller --timeout=20s
      # add a test intance
      - run: kubectl apply -f yaml/instance-samuel.yaml
      - run: kubectl wait --for=condition=somecondition doc/samuel --timeout 2
      # verify basic happy path outcomes have happened
      - run: kubectl get event --field-selector "involvedObject.kind=Document,involvedObject.name=samuel" | grep "HideRequested"
      - run: kubectl get doc -oyaml | grep -A1 finalizers | grep documents.kube.rs
```

Here we are loading a built container via [docker buildx](https://docs.docker.com/engine/reference/commandline/buildx_build/) from a different test job (named `docker` here) stashed as a [build artifact](https://github.com/actions/upload-artifact). Building images will be covered elsewhere, but you can see the [CI configuration for controller-rs](https://github.com/kube-rs/controller-rs/blob/main/.github/workflows/ci.yml) as a reference.

Once the image and the cluster (same [k3d] setup) is available, we can install the CRD, a test document, and the deployment yaml using whatever yaml pipeline we ~~want~~/_have_ to deal with (here [helm](https://helm.sh/)).

After installations and resources are ready (checked by [kubectl wait](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#wait) or a simpler `sleep` if you do not have enough conditions), we can verify that **basic changes have occurred** in the cluster.

<!-- TODO: link to docker / container / packaging doc here -->

!!! note "CRD installation"

    We separated the CRD installation and the deployment installation because CRD write access is generally a much stronger security requirement that is often controlled separately in a corporate environment.

<!-- TODO: move crd split note to packaging doc -->

### Benefits

These tests are **useful** because they cover the interface between the yaml and the application along with most **unknown-unknowns**. E.g. do you read a new evar in the app now? Did you typo something in RBAC, or provide insufficient access?

By having **a single e2e test** we can avoid most of those awkward post-release hot-fixes.

!!! note "Different approaches"

    It is possible to detect __some__ of these failure modes in other ways. Schema testing via [kubeconform](https://github.com/yannh/kubeconform), or client-side admission policy verification via [conftest](https://www.conftest.dev/) for [OPA](https://www.openpolicyagent.org/), or [kwctl](https://github.com/kubewarden/kwctl) for [kubewarden](https://www.kubewarden.io/), or [polaris CLI](https://github.com/FairwindsOps/polaris#cli) for [polaris](https://www.fairwinds.com/polaris) to name a few. You should consider these, but note that they are not foolproof. Policy tests generally verify security constraints, and schema tests are limited by schema completeness and openapi.

### Downsides

In addition to requiring slightly more complicated CI, the main **new downside** of using e2e tests over integration tests is **error handling complexity**; all possible failures modes can occur - often with bad error messages. On top of this, all the previous integration test downsides still apply.

As a result, we only want a **small number of e2e tests** as the signal to noise ratio is going to be low, and errors may not be obvious from failures.

## Summary

Each test category comes with its own unique set of benefits and challenges:

| Test Type    | Isolation             | Maintenance Cost                | Main Test Case        |
| ------------ | --------------------- | ------------------------------- | --------------------- |
| End-to-End   | :material-close: No   | Reliability + Isolation + Debug | Real IO + Full Smoke  |
| Integration  | :material-close: No   | Reliability + Isolation         | Real IO + Smoke       | 
| Unit w/mocks | :material-check: Yes  | Complexity + Readability        | Substitute IO         |
| Unit         | :material-check: Yes  | Unrealistic Scenarios           | Non-IO                |

The high cost of end-to-end and integration tests is almost entirely due to reliability issues with clusters on CI that ends up being a constant cost. The lack of test isolation in these real environments also make them more attractive as a form of **sanity verification**/smoke.

Focusing on the **lower end** of the test pyramid (by separating the IO code from your business logic, or by mocking liberally), and proving a few specialized tests at the top end, is likely to to have the biggest **benefit-to-pain ratio**. As an exercise in redundancy, [controller-rs does everything](https://github.com/kube-rs/controller-rs/blob/main/.github/workflows/ci.yml), and can be inspected as __a__ reference.

--8<-- "includes/abbreviations.md"
--8<-- "includes/links.md"

[//begin]: # "Autogenerated link references for markdown compatibility"
[reconciler]: reconciler "The Reconciler"
[reconciler##using-context]: reconciler "The Reconciler"
[//end]: # "Autogenerated link references"
