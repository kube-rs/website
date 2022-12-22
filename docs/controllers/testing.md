# Testing

This chapter covers various types of tests you can write, and what each test type is most appropriate for.

## Terminology

We will loosely follow [test definitions from kube](https://github.com/kube-rs/kube/blob/main/CONTRIBUTING.md#testing) and outline four types of tests:

- **End to End tests** (requires Kubernetes through an in-cluster Client)
- **Integration tests** (requires Kubernetes)
- **Mocked unit tests** (requires mocking Kubernetes dependencies)
- **Unit tests & Documentation Tests** (no Kubernetes calls)

These definitions provide a standard __test pyramid__ where the maintenance costs generally goes down - while the reliability goes down - the further up the list you go.

## Unit Tests

The simplest type of test, with the smallest amount of maintenance costs, but best when you separate non-IO logic from IO and [test your behavior sans-IO](https://sans-io.readthedocs.io/).

The usual caveats for unit tests applies:

- don't test too deep (private interface tests have a maintenance cost)
- don't blindly pursue 100% coverage from unit tests

If you have some business logic sitting in a module disconnected from the Kubernetes interaction (like some state machinery) then standard unit tests are a great choice.

Controller testing is in general hard to do with plain unit tests though, as you usually end up with a sizable code chunk heavily intertwined with IO operations through Kubernetes object interactions. You **could** move up the test pyramid and do full-scale integration testing, but you could also stay in unit-test land by mocking out your network dependencies (sacrificing a bit of test code verbosity for test reliability).

### Unit Tests with Mocks

It is possible to to test your reconciler and IO logic while retain the speed and isolation of unit tests by using mocks. This is common practice to avoid having to bring in your all your dependencies and is typically done through crates such as [wiremock](https://crates.io/crates/wiremock), [mockito](https://crates.io/crates/mockito), [tower-test](https://crates.io/crates/tower-test), and [mockall](https://crates.io/crates/mockall).

Out of these, [tower-test](https://crates.io/crates/tower-test) integrates into the [`Client`] out of the box without needing to hijack anything so it's the one we will focus on.

<!-- TODO: links to other use cases with wiremock? -->

To create a mocked [`Client`], it is sufficient to:

```rust
fn mock_client() -> Client {
    let (mock_service, handle) = tower_test::mock::pair::<Request<Body>, Response<Body>>();
    Client::new(mock_service, "default")
}
```

using the generic:

- [`hyper::Body`](https://docs.rs/hyper/latest/hyper/struct.Body.html)
- [`http::Request`](https://docs.rs/http/latest/http/request/struct.Request.html) + [`http::Response`](https://docs.rs/http/latest/http/response/struct.Response.html)

This `Client` can then be passed into to the [reconciler##using-context] through its context argument and you can test this directly. However, this does require a bit of boilerplate because there is nothing equivalent to [`envtest`](https://book.kubebuilder.io/reference/envtest.html) in Rust ([so far](https://github.com/kube-rs/kube/issues/1108)).

Thus to mock out calls to the apiserver you need some extra boilerplate:

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

Here we have made a some apiserver mock wrapper that will run certain scenarios.
Each scenario calls a number of handler functions. Here we only have made one for `handle_status_patch`, but more are available in [controller-rs/fixtures.rs](https://github.com/kube-rs/controller-rs/blob/main/src/fixtures.rs).

Running the tests themselves can after this get quite short and readable:

```rust
#[tokio::test]
async fn finalized_doc_causes_status_patch() {
    let (testctx, fakeserver) = Context::test();
    let doc = Document::test();
    let mocksrv = fakeserver.run(Scenario::StatusPatch(doc.clone()));
    reconcile(Arc::new(doc), testctx).await.expect("reconciler");
    timeout_after_1s(mocksrv).await;
}
```

!!! note "Hiding some details"

    Test functions to create the rest of the reconciler context and a test document used by a reconciler are not shown, see [controller-rs/fixtures.rs](https://github.com/kube-rs/controller-rs/blob/main/src/fixtures.rs) for a relatively small `Context`. Note that the more things you pass in to your reconciler the larger your `Context` will be, and the more stuff you will want to mock. 

Is this sufficient? We want to verify that:

1. we responded to the all messages in the scenario
2. we did not see any unexpected messages.

This is satisfied because:

1. Each scenario blocked on sequential api calls to happen (we await each message), so mockserver's joinhandle will not resolve until **every** expected message in the given scenario has happened (hence the timeout to avoid an infinite hang) 
2. If the mock server is receiving more Kubernetes calls than expected the reconciler will error with a `KubeError(Service(Closed(())))` caught by the `expect`

## Integration Tests

Integration tests are easy to write, and lets you verify that the IO components of your controller is doing the right thing.

Suppose you have a function that is publishing an event via an event [Recorder]:

```rust
async fn publish_event(client: Client, doc: &Document) -> Result<()> {
    let recorder = Recorder::new(client, "my-controller".into(), doc.object_ref(&()))
    recorder
        .publish(Event {
            type_: EventType::Normal,
            reason: "HiddenDoc".into(),
            note: Some(format!("Hiding `{name}`")),
            action: "Reconciling".into(),
            secondary: None,
        })
        .await?;
    Ok(())
}
```

You can't really unit test this function without a working [Client]. But because `kube` let's you use `Client::try_default()` to get a working client no matter what environment you are in (local development with a kubeconfig vs. in-cluster via evar tokens), you can just create a `#[test]` that works against any cluster you have running in the background:

```rust
#[tokio::test]
#[ignore] // needs a cluster
async fn get_doc_crd() -> Result<(), Box<dyn std::error::Error>> {
    let client = Client::try_default().await?;
    let events: Api<Event> = Api::all(client);
    let doc = Document::test();
    publish_event(client, &doc).await?;

    let doc_crd = crds.get("documents.kube.rs").await?; 
    Ok(())
}
```

The problem is that you need a cluster and all the problems it brings.




Setting up a cluster for integration tests is usually pretty straight forward. Here is a GitHub Actions setup:

```yaml
  integration:
    runs-on: ubuntu-latest
    strategy:
      # Prevent GitHub from cancelling all in-progress jobs when a matrix job fails.
      fail-fast: false
      matrix:
        # Run these tests against older clusters as well
        k8s: [v1.20, latest]
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


and in a CI environment setting one up and running one on every commit is slow, error-prone, and generally pushes your tests into reusing a single "shared environment".

## End to End Tests

The most expensive type of test.

For a controller this would typically be deploying your controller into a cluster, and then checking that it performs the operations that is expected to perform.

This type of test often do not even require any additional rust code because it is treating the whole controller as a large blackbox that you simply verify behavior of.

It is useful to have one of these as a sanity verification of your:

- packaging process (yaml / docker / oci artifacts)
- high level behaviour

and as such it functions as a high level smoke test that you can test usually with a small set of CI steps using `kubectl`

```yaml
- run: kubectl apply -f crd.yaml
- run: kubectl wait --for=condition=established mycrd
- run: helm template mychart | kubectl apply -f -
- run: kubectl wait --for=condition=running deployment/??? mydeployment --timeout=60s
- run: kubectl apply -f test_instance.yaml
- run: kubectl wait --for=some-condition-expected-to-happen some-dependent-resource/with-name
```

We have separated the CRD installation and the controller installation into two steps here (because CRD mutation is a stronger security requirement than deployment application and is usually more tightly controlled in a corporate environment), but you may wish to package these together.

Note that it is possible to run a simplified variant of this type of test by doing a `cargo run` rather than container build followed by a `kubectl apply` of your deployment yaml, but this would leave your deployment artifact (and in-cluster specific code pathways) untested until deployment time. This often causes awkward hot fixes post-release when you screwed up an evar or something in your yaml. Granted, you can minimize some of these types of errors through other means (e.g. [schema tests](https://github.com/yannh/kubeconform)), this is not always foolproof. Therefore, it's usually good to have one complete end-to-end test just to cover these cases, along with any other unknown unknowns.



--8<-- "includes/abbreviations.md"
--8<-- "includes/links.md"


