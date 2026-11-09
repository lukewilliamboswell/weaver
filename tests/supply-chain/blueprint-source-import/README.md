# Source package SBOM import regression

Blueprint 0.7 rejected the valid source supplier below in a native inventory.
Blueprint 0.8 fixes [issue 61](https://github.com/lukewilliamboswell/roc-blueprint/issues/61).
These inert inputs preserve the actual generated roc-ansi candidate SBOM used
to report it; they do not assert that 0.13.3 has been published.

Run the regression with the checksum-locked Blueprint 0.12 SBOM tool:

```sh
python3 tests/supply-chain/blueprint-source-import/check.py
```

It checks source and both Linux native inventories, the conservative defaults
added while normalizing the unchanged v1 composition, and each refusal below.
It preserves the supplier's document digest, source identity and incomplete
coverage. No unknown fact becomes a standard completeness claim.

For individual inspections with the native SBOM tool (no compiler needed):

```sh
blueprint-sbom inspect Spec Lock composition.json source source-inventory.json
blueprint-sbom inspect Spec Lock composition.json x86_64-linux native-inventory.json
blueprint-sbom inspect Spec Lock composition.json aarch64-linux arm-inventory.json
```

All three must succeed and preserve the supplier's source identity. Outputs are
write-once: use new filenames for each run. Spec/Lock pin the supplied source
archive's SHA-256; composition.json embeds the supplier document and binds its
subject filename, digest and version to that pin. No supplier artifact is fetched
or executed. The compiler/native dependency closure of a downstream executable
is a separate responsibility from importing a source archive's graph.

Changing imported_documents[0].sha256 must reject with `imported SBOM content
digest mismatch`. Changing imported_documents[0].subject.sha256 or .version must
reject with `import subject filename/version/SHA256 mismatch`. Relabelling the
source import's target as native must still reject. Blueprint's release fixture
contract adds incompatible native-architecture and full bind/readback cases.
