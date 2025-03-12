# Features

All public features are exposed through `kube` in [kube's Cargo.toml](https://github.com/kube-rs/kube/blob/main/kube/Cargo.toml).


## Stable Features

| Feature     | Enables                            | Default | Significant Inclusions       |
| ----------- | ---------------------------------- | ------- | ---------------------------- |
| config      | [Config]                           | yes     | [kube-client] partial        |
| client      | [Client] + [Api]                   | yes     | [kube-client], [hyper], [tower] |
| runtime     | [Controller] + [watcher]           | no      | [kube-runtime]               |
| derive      | [CustomResource]                   | no      | [kube-derive], [syn], [quote]|
| openssl-tls | tls via openssl                    | no      | [openssl], [hyper-openssl]   |
| rustls-tls  | tls via rustls                     | [yes]   | [rustls], [hyper-rustls]     |
| ring        | rustls via ring                    | yes     | [ring]                       |
| aws-lc-rs   | rustls via aws-lc-rs               | no      | [aws-lc-rs]                  |
| ws          | [Execute], [Attach], [Portforward] | no      | [tokio-tungstenite]          |
| gzip        | gzip compressed transport          | no      | [tower-http] feature         |
| jsonpatch   | [Patch] using jsonpatch            | no      | [json_patch]                 |
| admission   | [admission] module                 | no      | [json_patch]                 |
| socks5      | local cluster [socks5] proxying    | no      | [hyper-socks2]               |
| http-proxy  | local cluster http proxying        | no      | [hyper-http-proxy]           |
| oauth       | local cluster oauth for GCP        | no      | [tame-oauth]                 |
| oidc        | local cluster [oidc] auth          | no      | none                         |
| webpki-roots| Mozilla's root certificates        | no      | [webpki-roots]               |

!!! note "Client dependencies"

    Most of these features depend on having the `client` feature (and thus the `config` feature) enabled as they would not be much use without them.

!!! warning "--no-default-features"

    If you turn off all default features (say, to change tls stacks), you also turn off the normal `client` default feature. Without default features you get a crate roughly equivalent to [kube-core].

## Unstable Features

- `unstable-runtime` for stream sharing and controller streams interface tracked in [#1080](https://github.com/kube-rs/kube/issues/1080)
- `unstable-client` for client exts tracked in [#1032](https://github.com/kube-rs/kube/issues/1032)
- `kubelet-debug` for kubelet debug api access - untracked

---

[yes]: https://github.com/kube-rs/kube/releases/tag/0.86.0
[socks5]: https://kubernetes.io/docs/tasks/extend-kubernetes/socks5-proxy-access-api/
[oidc]: https://kubernetes.io/docs/reference/access-authn-authz/authentication/#openid-connect-tokens
[admission]: https://docs.rs/kube/latest/kube/core/admission/index.html
[Execute]: https://docs.rs/kube/latest/kube/api/trait.Execute.html
[Attach]: https://docs.rs/kube/latest/kube/api/trait.Attach.html
[Portforward]: https://docs.rs/kube/latest/kube/api/trait.Portforward.html


--8<-- "includes/abbreviations.md"
--8<-- "includes/links.md"
