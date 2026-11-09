#!/usr/bin/env python3
"""Exercise the locked SBOM tool against the original v1 supplier fixture."""

import copy
import json
import subprocess
import tempfile
from pathlib import Path


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def inspect(fixture, composition, target, output):
    return subprocess.run(
        ["blueprint", "run", "sbom-tool", "--", "inspect",
         str(fixture / "Spec"), str(fixture / "Lock"), str(composition),
         target, str(output)],
        capture_output=True, text=True, check=False,
    )


def main():
    fixture = Path(__file__).resolve().parent
    original = json.loads((fixture / "composition.json").read_text())
    require(original["profile"] == "blueprint-spdx-3.0-v1", "fixture must stay v1")
    supplier = original["imported_documents"][0]
    with tempfile.TemporaryDirectory(prefix="weaver-source-import-") as directory:
        temporary = Path(directory)
        for target in ("source", "x86_64-linux", "aarch64-linux"):
            output = temporary / f"{target}.json"
            result = inspect(fixture, fixture / "composition.json", target, output)
            require(result.returncode == 0, result.stderr or result.stdout)
            inventory = json.loads(output.read_text())
            require(inventory["target"] == target, "inventory target changed")
            require(inventory["inputs"] == original["inputs"], "input binding changed")
            require(all(r in inventory["relationships"] for r in original["relationships"]),
                    "source dependency relationship lost")
            components = {c["id"]: c for c in inventory["components"]}
            for component in components.values():
                require(component["kind"] == "unknown", "invented component kind")
                require(component["copyright"] == "NOASSERTION", "invented copyright")
                require(component["attribution"] == "NOASSERTION", "invented attribution")
                require(component["source_refs"] == [], "invented source reference")
                require(component["package_url"] == "", "invented package URL")
                require(component["target"] == "source", "source import relabelled native")
            for key in ("sha256", "version"):
                require(components["dep"][key] == supplier["subject"][key],
                        f"locked supplier {key} changed")
                require(components["dep-sbom-Subject"][key] == supplier["subject"][key],
                        f"imported supplier {key} changed")
            require(supplier["sha256"] in components["dep-sbom-Subject"]["modified"],
                    "supplier document digest lost")
            coverage = inventory["coverage"]
            require(all(c["component"] == c["aspect"] == "" for c in coverage),
                    "legacy coverage gained standard completeness")
            require(any(c["scope"] == "import:dep-sbom" and c["status"] == "incomplete"
                        for c in coverage), "supplier uncertainty lost")
            require(any(c["scope"] == "import:dep-sbom:build-tool-closure"
                        and c["status"] == "incomplete" for c in coverage),
                    "supplier compiler closure gap lost")
            print(f"PASS {target}: conservative defaults, source identity and coverage")

        for name, field, value, diagnostic in (
            ("document-digest", "sha256", "0" * 64, "imported SBOM content digest mismatch"),
            ("subject-digest", "subject.sha256", "0" * 64, "import subject filename/version/SHA256 mismatch"),
            ("subject-version", "subject.version", "0.0.0", "import subject filename/version/SHA256 mismatch"),
            ("native-label", "target", "x86_64-linux", "imported document subject target mismatch"),
        ):
            changed = copy.deepcopy(original)
            record = changed["imported_documents"][0]
            if field.startswith("subject."):
                record["subject"][field.split(".")[1]] = value
            else:
                record[field] = value
            path = temporary / f"{name}-composition.json"
            path.write_text(json.dumps(changed))
            output = temporary / f"{name}-inventory.json"
            result = inspect(fixture, path, "x86_64-linux", output)
            require(result.returncode != 0, f"accepted {name}")
            require(diagnostic in result.stderr + result.stdout, result.stderr or result.stdout)
            require(not output.exists(), f"refused {name} left an inventory")
            print(f"PASS refused {name}: {diagnostic}")


if __name__ == "__main__":
    main()
