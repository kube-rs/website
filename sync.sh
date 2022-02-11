#!/bin/bash
set -eo pipefail

sync() {
    repopath="$1"
    namelocal="$2"
    header="$3"
    echo "<!--GENERATED FROM https://github.com/blob/${repopath} - CHANGES MUST BE MADE THERE -->" > "${namelocal}"
    if [ -n "${header}" ]; then
        echo "${header}" >> "${namelocal}"
    fi
    # TODO: swap to use the github api tool to avoid being rate limited
    curl -sSL "https://raw.githubusercontent.com/${repopath}" >> "${namelocal}"
}

main() {
    sync kube-rs/.github/main/maintainers.md docs/maintainers.md
    sync kube-rs/kube-rs/master/CONTRIBUTING.md docs/contributing.md
    sync kube-rs/kube-rs/master/ADOPTERS.md docs/adopters.md
    sync kube-rs/.github/main/code-of-conduct.md docs/code-of-conduct.md
    sync kube-rs/.github/main/SECURITY.md docs/security.md

    # main readme requires some re-formatting to be used as getting-started
    sync kube-rs/kube-rs/master/README.md docs/getting-started.md
    # drop the first paragraph
    sd "# kube-rs[\w\W]*## Installation" "# Getting Started\n## Installation" docs/getting-started.md

    # changelog requires some re-formatting (don't want to change all automation scripts in kube-rs repo)
    sync kube-rs/kube-rs/master/CHANGELOG.md docs/changelog.md "# Changelog"
    sd "^(.+ / [\d-]+)\n===================" "## \$1" docs/changelog.md
    sd "UNRELEASED\n===================" "## Unreleased" docs/changelog.md

    # TODO: maybe move these files into this repo as they have no interaction effects
    sync kube-rs/.github/main/governance.md docs/governance.md
    sync kube-rs/.github/main/TOOLS.md docs/tools.md
    sync kube-rs/kube-rs/master/architecture.md docs/architecture.md
}

# shellcheck disable=SC2068
main $@
