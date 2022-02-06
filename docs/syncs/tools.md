# Tools we use

All repositories herein are buildable using FLOSS tools, and they are listed herein:

## User Dependencies

Dependencies a user needs to use kube-rs.

- [Rust](https://www.rust-lang.org/)
- various crates satisfying our [license allowlist](https://github.com/kube-rs/kube-rs/blob/master/deny.toml)

## Development Dependencies

Dependencies a developer **might** find helpful to develop on kube-rs.

### Build Dependencies

CLIs that are used for occasional build or release time manipulation. Maintainers need these.

- [fd](https://github.com/sharkdp/fd)
- [jq](https://stedolan.github.io/jq/)
- [just](https://github.com/casey/just)
- [sd](https://github.com/chmln/sd)
- [rg](https://github.com/BurntSushi/ripgrep)
- [curl](https://curl.se/)
- [cargo-release](https://github.com/crate-ci/cargo-release)

GNU tools like `make` + `grep` + `head` + `tail` + `awk` + `sed`, are also referenced a handful of times, but are generally avoided due to more modern tools above.

### CI Dependencies

- [cargo-audit](https://github.com/RustSec/rustsec/tree/main/cargo-audit)
- [cargo-deny](https://github.com/EmbarkStudios/cargo-deny)
- [cargo-msrv](https://github.com/foresterre/cargo-msrv)
- [cargo-tarpaulin](https://github.com/xd009642/tarpaulin)

### Integration Tests

CLIs that are used in integration tests, or referenced as ways recommended to test locally.

- [k3d](https://k3d.io/)
- [tilt](https://tilt.dev/)
- [docker/cli](https://github.com/docker/cli)
