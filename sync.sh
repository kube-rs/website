#!/bin/bash
set -euxo pipefail

curl -sSL https://raw.githubusercontent.com/kube-rs/.github/main/maintainers.md -o docs/syncs/maintainers.md
curl -sSL https://raw.githubusercontent.com/kube-rs/kube-rs/master/CONTRIBUTING.md -o docs/syncs/contributing.md
curl -sSL https://raw.githubusercontent.com/kube-rs/kube-rs/master/ADOPTERS.md -o docs/syncs/adopters.md
curl -sSL https://raw.githubusercontent.com/kube-rs/kube-rs/master/CHANGELOG.md -o docs/syncs/changelog.md
curl -sSL https://raw.githubusercontent.com/kube-rs/kube-rs/master/README.md -o docs/syncs/getting-started.md
curl -sSL https://raw.githubusercontent.com/kube-rs/.github/main/code-of-conduct.md -o docs/syncs/code-of-conduct.md
curl -sSL https://raw.githubusercontent.com/kube-rs/.github/main/SECURITY.md -o docs/syncs/security.md

# TODO: maybe move these files into this repo as they have no interaction effects
curl -sSL https://raw.githubusercontent.com/kube-rs/.github/main/governance.md -o docs/syncs/governance.md
curl -sSL https://raw.githubusercontent.com/kube-rs/.github/main/TOOLS.md -o docs/syncs/tools.md
curl -sSL https://raw.githubusercontent.com/kube-rs/kube-rs/master/architecture.md -o docs/syncs/architecture.md

# TODO: consider building this website from kube-rs repo directly to get links working?
# .. but this means we cannot get docs from other repos
