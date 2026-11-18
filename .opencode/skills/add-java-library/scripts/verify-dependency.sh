#!/usr/bin/env bash
# Verify a Maven coordinate and its version against Maven Central, and report
# whether the project's Spring Boot BOM manages it (including BOMs that
# spring-boot-dependencies imports, such as jackson-bom or junit-bom).
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


def properties(root, ns, depth=0):
    """Effective <properties>, inheriting from parent POMs (child wins)."""
    inherited = {}
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
        dg = (dep.findtext(ns + "groupId") or "").strip()
        da = (dep.findtext(ns + "artifactId") or "").strip()
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
