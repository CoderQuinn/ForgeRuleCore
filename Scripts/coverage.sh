#!/bin/bash

set -euo pipefail

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "${script_directory}/.." && pwd)"
readonly package_root="${repository_root}/ForgeRuleCore"
readonly source_root="${package_root}/Sources/ForgeRuleCore"
readonly coverage_threshold="95.00"
readonly summary_directory="${package_root}/.build/coverage"
readonly summary_path="${summary_directory}/production-summary.md"
readonly source_data_path="${summary_directory}/production-files.json"

for command_name in python3 swift; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "error: required command '${command_name}' was not found" >&2
        exit 1
    fi
done

cd "${package_root}"
swift package resolve
swift package clean
swift test \
    --enable-code-coverage \
    -Xcc -fprofile-instr-generate \
    -Xcc -fcoverage-mapping

readonly coverage_path="$(swift test --show-codecov-path)"
if [[ ! -s "${coverage_path}" ]]; then
    echo "error: SwiftPM did not produce a coverage report" >&2
    exit 1
fi

mkdir -p "${summary_directory}"
python3 - \
    "${coverage_path}" \
    "${source_root}" \
    "${source_data_path}" \
    "${summary_path}" \
    "${coverage_threshold}" <<'PY'
import json
import os
import sys

coverage_path, source_root, data_path, summary_path, threshold_text = sys.argv[1:]
source_prefix = os.path.realpath(source_root) + os.sep
threshold = float(threshold_text)

with open(coverage_path, encoding="utf-8") as source:
    report = json.load(source)

files = []
for data in report.get("data", []):
    for entry in data.get("files", []):
        filename = os.path.realpath(entry.get("filename", ""))
        if not filename.startswith(source_prefix):
            continue
        relative_path = filename[len(source_prefix):]
        if relative_path.startswith("GeoMMDB/libmaxminddb/"):
            continue
        lines = entry.get("summary", {}).get("lines", {})
        files.append({
            "component": relative_path.split(os.sep, 1)[0],
            "file": relative_path.replace(os.sep, "/"),
            "covered": int(lines.get("covered", 0)),
            "count": int(lines.get("count", 0)),
        })

files.sort(key=lambda item: item["file"])
if not files:
    raise SystemExit("error: coverage report contains no first-party production files")

observed = {item["file"] for item in files}
required = {
    "Core/RuleEngine.swift",
    "GeoMMDB/GeoMMDBBridge/GeoMMDBBridge.c",
}
missing = sorted(required - observed)
if missing:
    raise SystemExit("error: coverage report is missing: " + ", ".join(missing))

with open(data_path, "w", encoding="utf-8") as output:
    json.dump(files, output, indent=2, sort_keys=True)
    output.write("\n")

def percent(covered, count):
    return 0.0 if count == 0 else 100.0 * covered / count

total_covered = sum(item["covered"] for item in files)
total_count = sum(item["count"] for item in files)
total_percent = percent(total_covered, total_count)

components = {}
for item in files:
    covered, count = components.get(item["component"], (0, 0))
    components[item["component"]] = (
        covered + item["covered"],
        count + item["count"],
    )

lines = [
    "# Production source coverage",
    "",
    "Only first-party files under `Sources/ForgeRuleCore/` are counted; tests and vendored `libmaxminddb` sources are excluded.",
    "",
    "| Component | Covered lines | Total lines | Line coverage |",
    "| --- | ---: | ---: | ---: |",
]
for component in sorted(components):
    covered, count = components[component]
    lines.append(f"| {component} | {covered} | {count} | {percent(covered, count):.2f}% |")
lines.extend([
    f"| **Total** | **{total_covered}** | **{total_count}** | **{total_percent:.2f}%** |",
    "",
    f"Required total line coverage: {threshold:.2f}%",
    "",
    "## Files",
    "",
    "| Production file | Covered lines | Total lines | Line coverage |",
    "| --- | ---: | ---: | ---: |",
])
for item in files:
    lines.append(
        f"| `{item['file']}` | {item['covered']} | {item['count']} | "
        f"{percent(item['covered'], item['count']):.2f}% |"
    )

with open(summary_path, "w", encoding="utf-8") as output:
    output.write("\n".join(lines) + "\n")

print("\n".join(lines))
if total_percent < threshold:
    raise SystemExit(
        f"error: production line coverage {total_percent:.2f}% is below {threshold:.2f}%"
    )
print(f"Coverage gate passed: {total_percent:.2f}% >= {threshold:.2f}%")
PY
