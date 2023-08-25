# Upgrading

You can upgrade `kube` and it's sibling crate `k8s-openapi` using normal Rust methods to upgrade.

!!! warning "`kube` and `k8s-openapi` are siblings"

    `kube` depends on `k8s-openapi`, but users need to select the Kubernetes version on `k8s-openapi`. Whenever `k8s-openapi` releases a new version, `kube` releases a new version shortly after.

We recommend you bump both `kube` and `k8s-openapi` crates at the same time to avoid build issues.

## Command Line

Using `cargo upgrade` via [cargo-edit]:

```sh
cargo upgrade -p kube -p k8s-openapi -i
```

## Dependabot

[Configure](https://docs.github.com/en/code-security/dependabot/dependabot-version-updates/configuration-options-for-the-dependabot.yml-file) the `cargo` ecosystem on dependabot and [group](https://docs.github.com/en/code-security/dependabot/dependabot-version-updates/configuration-options-for-the-dependabot.yml-file#groups) `kube` and `k8s-openapi` upgrades together:

```yaml
  - package-ecosystem: "cargo"
    directory: "/"
    schedule:
      interval: "weekly"
    groups:
      kube:
        patterns:
          - kube
          - k8s-openapi
```

## Renovate

Add [package rules](https://docs.renovatebot.com/configuration-options/) for Kubernetes crates that [match on prefixes](https://docs.renovatebot.com/configuration-options/#matchpackageprefixes):

```json
packageRules: [
        {
            matchPackagePrefixes: [
                "kube",
                "k8s",
            ],
            groupName: "kubernetes crates",
            matchManagers: [
                "cargo"
            ],
        }
]
```

--8<-- "includes/abbreviations.md"
--8<-- "includes/links.md"
