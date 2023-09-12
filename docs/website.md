# Website

This website is hosted on [kube.rs](https://kube.rs) via github pages from the [kube-rs/website](https://github.com/kube-rs/website) repo, and accepts contributions in the form of pull requests to change the markdown files that generate the website.

## Structure

The [docs folder](https://github.com/kube-rs/website/tree/main/docs) contains all the resources that's inlined on the webpage and can be edited on this page using any editor.

It is recommended having markdown preview, wikilink, and the foam extension, but what is rendered is ultimately just generated from markdown with wikilinks.

## Synchronization

A subset of markdown documents show up in certain paths of the github contribution process and must remain in these original repos.

> Synchronized markdown documents **will be overwritten** if edited herein!

Notice the first line of these files contain a line like the following:

```sh
<!--GENERATED FROM
https://github.com/kube-rs/kube/blob/main/CONTRIBUTING.md
CHANGES MUST BE MADE THERE -->
```

These files **must be edited upstream** at the given path, and will be [synchronized](https://github.com/kube-rs/website/blob/main/sync.sh) to this site on the next kube release or sooner.
