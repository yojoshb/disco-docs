[Live Docs site](https://yojoshb.github.io/disco-docs/)

[Offline/Standalone Docs site download](https://github.com/yojoshb/disco-docs/releases)

## Documentation to install Red Hat OpenShift in a airgap/disconnected environment
Mostly regurgitates Red Hat's docs in a more streamlined fashion that may be easier to follow. Includes common installation scenario examples and is able to be used completely offline for ease-of-use (other than external links to Red Hat docs). This installation method is based on using the Agent-based Installer and associated tools (oc-mirror).

- [docs](./docs): All markdown files and assets for the site pages
- [_scripts](./_scripts/): A few cluster tooling/maintenance bash scripts
- [_dev](./_dev/): Dockerfile/Containerfile and scripts for creating a local containerized copy of the site


#### Docs are built using [mkdocs-material](https://github.com/squidfunk/mkdocs-material)
Additional Extensions used:
- [mkdocs-print-site-plugin](https://timvink.github.io/mkdocs-print-site-plugin/index.html)
- [mkdocs-to-pdf](https://mkdocs-to-pdf.readthedocs.io/en/latest/usage/)
- [mkdocs-autorefs](https://mkdocstrings.github.io/autorefs/)

