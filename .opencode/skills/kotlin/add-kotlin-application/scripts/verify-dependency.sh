#!/usr/bin/env bash
# Verify a Maven coordinate and its version against Maven Central, and report
# whether the project's Spring Boot BOM manages it (including BOMs that
# spring-boot-dependencies imports, such as jackson-bom or junit-bom).
#
# When the catalog defines a kotlin version key, also inspect the artifact's
# POM for the Kotlin version it declares, so a library built with newer Kotlin
# metadata is visible before a Kotlin module fails to compile.
#
# Usage:
#   verify-dependency.sh <group:artifact>              # latest releases + BOM status
#   verify-dependency.sh <group:artifact> <version>    # also assert version exists
#
# Exit codes:
#   0  coordinate (and version, if given) confirmed
#   1  coordinate or version not found on Maven Central
#   2  bad usage / missing curl
#
# Output is key=value lines so callers can grep deterministically.

set -u

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo "usage: $0 <group:artifact> [version]" >&2
    exit 2
fi

command -v curl >/dev/null 2>&1 || {
    echo "error: curl is required" >&2
    exit 2
}

coord="$1"
wanted="${2:-}"

case "$coord" in
    *:*) ;;
    *) echo "error: coordinate must be group:artifact (got '$coord')" >&2; exit 2 ;;
esac

group="${coord%%:*}"
artifact="${coord#*:}"

if [ -z "$group" ] || [ -z "$artifact" ]; then
    echo "error: coordinate must be group:artifact (got '$coord')" >&2
    exit 2
fi

group_path="$(printf '%s' "$group" | tr '.' '/')"
base="https://repo1.maven.org/maven2/${group_path}/${artifact}"
metadata_url="${base}/maven-metadata.xml"

xml="$(curl -fsS --max-time 20 "$metadata_url" 2>/dev/null)" || {
    echo "artifact_exists=false"
    echo "error: no maven-metadata.xml at $metadata_url" >&2
    exit 1
}

echo "artifact_exists=true"
echo "coordinate=${group}:${artifact}"

release="$(printf '%s' "$xml" | sed -n 's:.*<release>\([^<]*\)</release>.*:\1:p' | tail -1)"
if [ -z "$release" ]; then
    release="$(printf '%s' "$xml" | sed -n 's:.*<latest>\([^<]*\)</latest>.*:\1:p' | tail -1)"
fi
[ -n "$release" ] && echo "latest_release=${release}"

versions="$(printf '%s' "$xml" | grep -o '<version>[^<]*</version>' | sed 's/<[^>]*>//g')"

# Latest release that is not a pre-release qualifier (M1, RC2, -beta, ...).
stable="$(printf '%s\n' "$versions" \
    | grep -viE '[-.](alpha|beta|rc|cr|m|preview|ea|snapshot)[0-9]*$' \
    | tail -1)"
[ -n "$stable" ] && echo "latest_stable=${stable}"

# Newest last, for picking a real previous release.
[ -n "$versions" ] && printf '%s\n' "$versions" | tail -10 | sed 's/^/recent_version=/'

# Spring Boot BOM management check, when the catalog and python3 exist.
catalog="${CATALOG:-gradle/libs.versions.toml}"
boot_version=""
[ -f "$catalog" ] && boot_version="$(sed -n 's/^[[:space:]]*spring-boot[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$catalog" | head -1)"

if [ -z "$boot_version" ]; then
    echo "bom_checked=false"
    echo "note: no spring-boot version key found in ${catalog:-catalog}" >&2
elif ! command -v python3 >/dev/null 2>&1; then
    echo "bom_checked=false"
    echo "note: python3 not available; cannot inspect the BOM" >&2
else
    echo "bom_version=${boot_version}"
    python3 - "$group" "$artifact" "$boot_version" <<'PY'
import sys
import urllib.request
import xml.etree.ElementTree as ET

group, artifact, boot = sys.argv[1], sys.argv[2], sys.argv[3]
BASE = "https://repo1.maven.org/maven2"
CACHE = {}


def fetch(url):
    if url in CACHE:
        return CACHE[url]
    try:
        with urllib.request.urlopen(url, timeout=30) as response:
            CACHE[url] = response.read().decode("utf-8", "replace")
    except Exception:
        CACHE[url] = None
    return CACHE[url]


def pom_url(g, a, v):
    return f"{BASE}/{g.replace('.', '/')}/{a}/{v}/{a}-{v}.pom"


def parse(text):
    root = ET.fromstring(text)
    ns = root.tag.split("}")[0] + "}" if root.tag.startswith("{") else ""
    return root, ns


def project_properties(root, ns):
    """Implicit ${project.*} values from the POM's own (or parent) coordinates."""
    group = (root.findtext(ns + "groupId") or "").strip()
    artifact = (root.findtext(ns + "artifactId") or "").strip()
    version = (root.findtext(ns + "version") or "").strip()
    parent = root.find(ns + "parent")
    if parent is not None:
        group = group or (parent.findtext(ns + "groupId") or "").strip()
        version = version or (parent.findtext(ns + "version") or "").strip()
    values = {}
    if group:
        values["project.groupId"] = group
        values["pom.groupId"] = group
    if artifact:
        values["project.artifactId"] = artifact
        values["pom.artifactId"] = artifact
    if version:
        values["project.version"] = version
        values["pom.version"] = version
    return values


def properties(root, ns, depth=0):
    """Effective <properties>, inheriting from parent POMs (child wins)."""
    inherited = project_properties(root, ns)
    if depth < 3:
        parent = root.find(ns + "parent")
        if parent is not None:
            pg = (parent.findtext(ns + "groupId") or "").strip()
            pa = (parent.findtext(ns + "artifactId") or "").strip()
            pv = (parent.findtext(ns + "version") or "").strip()
            if pg and pa and pv and "$" not in pv:
                parent_pom = fetch(pom_url(pg, pa, pv))
                if parent_pom:
                    try:
                        proot, pns = parse(parent_pom)
                        inherited.update(properties(proot, pns, depth + 1))
                    except ET.ParseError:
                        pass
    own = {}
    element = root.find(ns + "properties")
    if element is not None:
        for child in list(element):
            own[child.tag.split("}")[-1]] = (child.text or "").strip()
    inherited.update(own)
    return inherited


def resolve(value, props):
    seen = 0
    while value.startswith("${") and value.endswith("}") and seen < 5:
        key = value[2:-1]
        if key not in props:
            return None
        value = props[key]
        seen += 1
    return None if "$" in value else value


def managed_version(text, want_group, want_artifact, depth=0):
    try:
        root, ns = parse(text)
    except ET.ParseError:
        return None

    dm = root.find(ns + "dependencyManagement")
    if dm is None:
        return None
    deps = dm.find(ns + "dependencies")
    if deps is None:
        return None

    props = properties(root, ns)
    imports = []
    for dep in deps.findall(ns + "dependency"):
        raw_group = (dep.findtext(ns + "groupId") or "").strip()
        raw_artifact = (dep.findtext(ns + "artifactId") or "").strip()
        dg = resolve(raw_group, props) or raw_group
        da = resolve(raw_artifact, props) or raw_artifact
        dv = (dep.findtext(ns + "version") or "").strip()
        scope = (dep.findtext(ns + "scope") or "").strip()
        if scope == "import":
            resolved = resolve(dv, props)
            imports.append((dg, da, resolved))
        elif dg == want_group and da == want_artifact:
            return resolve(dv, props) or dv or "(managed)"

    if depth >= 3:
        return None
    for ig, ia, iv in imports:
        if not (ig and ia and iv):
            continue
        imported = fetch(pom_url(ig, ia, iv))
        if not imported:
            continue
        found = managed_version(imported, want_group, want_artifact, depth + 1)
        if found:
            return found
    return None


boot_pom = fetch(pom_url("org.springframework.boot", "spring-boot-dependencies", boot))
if boot_pom is None:
    print("bom_checked=false")
    print("warning: could not fetch spring-boot-dependencies POM", file=sys.stderr)
    sys.exit(0)

found = managed_version(boot_pom, group, artifact)
if found:
    print("managed=true")
    if "$" in found:
        print("managed_version_unresolved=true")
    print(f"managed_version={found}")
else:
    print("managed=false")
    print("managed_version=")
PY
fi

# Kotlin metadata check, when the catalog defines a kotlin version key.
kotlin_project_version=""
[ -f "$catalog" ] && kotlin_project_version="$(sed -n 's/^[[:space:]]*kotlin[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$catalog" | head -1)"

if [ -z "$kotlin_project_version" ]; then
    echo "kotlin_checked=false"
else
    inspect_version="${wanted:-$stable}"
    echo "kotlin_project_version=${kotlin_project_version}"
    if [ -z "$inspect_version" ]; then
        echo "kotlin_checked=false"
        echo "note: no release version available to inspect for Kotlin metadata" >&2
    elif ! command -v python3 >/dev/null 2>&1; then
        echo "kotlin_checked=false"
        echo "note: python3 not available; cannot inspect the POM for Kotlin metadata" >&2
    else
        python3 - "$group" "$artifact" "$inspect_version" "$kotlin_project_version" <<'PY'
import re
import sys
import urllib.request
import xml.etree.ElementTree as ET

group, artifact, version, project = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
BASE = "https://repo1.maven.org/maven2"
pom = f"{BASE}/{group.replace('.', '/')}/{artifact}/{version}/{artifact}-{version}.pom"

try:
    with urllib.request.urlopen(pom, timeout=30) as response:
        text = response.read().decode("utf-8", "replace")
except Exception:
    print("kotlin_checked=false")
    print("kotlin_compatibility=unknown")
    print("note: could not fetch the POM to inspect Kotlin metadata", file=sys.stderr)
    sys.exit(0)

try:
    root = ET.fromstring(text)
except ET.ParseError:
    print("kotlin_checked=false")
    print("kotlin_compatibility=unknown")
    print("note: could not parse the POM to inspect Kotlin metadata", file=sys.stderr)
    sys.exit(0)

ns = root.tag.split("}")[0] + "}" if root.tag.startswith("{") else ""

props = {}
element = root.find(ns + "properties")
if element is not None:
    for child in list(element):
        props[child.tag.split("}")[-1]] = (child.text or "").strip()


def resolve(value):
    seen = 0
    while value.startswith("${") and value.endswith("}") and seen < 5:
        key = value[2:-1]
        if key not in props:
            return None
        value = props[key]
        seen += 1
    return None if "$" in value else value


def looks_like_version(value):
    return bool(re.match(r"^\d+\.\d+(\.\d+)?", value or ""))


def major_minor(value):
    parts = re.findall(r"\d+", value or "")
    return tuple(int(p) for p in parts[:2]) if len(parts) >= 2 else None


candidates = []
for key, value in props.items():
    if "kotlin" in key.lower():
        resolved = resolve(value)
        if resolved and looks_like_version(resolved):
            candidates.append(resolved)

for dependency in root.iter(ns + "dependency"):
    dep_group = (dependency.findtext(ns + "groupId") or "").strip()
    dep_artifact = (dependency.findtext(ns + "artifactId") or "").strip()
    dep_version = (dependency.findtext(ns + "version") or "").strip()
    if dep_group == "org.jetbrains.kotlin" and dep_artifact == "kotlin-stdlib":
        resolved = resolve(dep_version)
        if resolved and looks_like_version(resolved):
            candidates.append(resolved)

library_version = None
library_key = None
for candidate in candidates:
    key = major_minor(candidate)
    if key and (library_key is None or key > library_key):
        library_key = key
        library_version = candidate

project_key = major_minor(project)

print("kotlin_checked=true")
print("kotlin_compatibility_basis=pom_declared_kotlin")
if library_version is None:
    print("kotlin_library_version=unknown")
    print("kotlin_compatibility=unknown")
    print("note: the POM does not declare a Kotlin version; compatibility not assessed", file=sys.stderr)
elif project_key is None:
    print(f"kotlin_library_version={library_version}")
    print("kotlin_compatibility=unknown")
    print(f"note: could not parse the project kotlin version '{project}'", file=sys.stderr)
elif library_key <= project_key:
    print(f"kotlin_library_version={library_version}")
    print("kotlin_compatibility=ok")
else:
    print(f"kotlin_library_version={library_version}")
    print("kotlin_compatibility=review")
    print(
        f"note: library declares Kotlin {library_version}, newer than project {project}; "
        "its Kotlin metadata may be unreadable. Do not bump Kotlin silently.",
        file=sys.stderr,
    )
PY
    fi
fi

if [ -n "$wanted" ]; then
    if printf '%s' "$versions" | grep -qx "$wanted"; then
        echo "version_exists=true"
        echo "version=${wanted}"
        http_status="$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "${base}/${wanted}/")"
        echo "artifact_dir_http=${http_status}"
    else
        echo "version_exists=false"
        echo "version=${wanted}"
        echo "error: version ${wanted} is not published for ${group}:${artifact} (latest stable: ${stable:-unknown})" >&2
        exit 1
    fi
fi
