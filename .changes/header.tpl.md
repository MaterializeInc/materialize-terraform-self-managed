# Upgrading

Most of the time, you just need to bump the `ref=<tag>` in all modules. We recommend that you bump all modules to the same version in the same `terraform apply`. We frequently make changes that assume related changes in dependent modules.

Upgrades of the materialize version are included in our tagged releases. We do not recommend overriding the Materialize version, orchestratord version, or helm chart version. Updating the module tags will automatically pick up the latest versions of these components.

We follow semantic versioning with our tags. If a particular version requires additional actions or contains breaking changes, we list them below. Read every section between your current version and the one you upgrade to.
