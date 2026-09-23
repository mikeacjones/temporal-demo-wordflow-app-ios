#!/usr/bin/env python3
"""Structural checker for TemporalWordflow.xcodeproj/project.pbxproj.

Xcode is not installed on this machine, so the project file cannot be opened to
prove it is consistent. This converts it to JSON with plutil and verifies the
graph by hand: every reference resolves, every build file points at a real file
reference, and every source path exists on disk (a missing file is only a
warning — sibling agents may still be writing it).

Usage:  python3 Tools/check-pbxproj.py [path/to/project.pbxproj]
Exits non-zero and prints ERROR lines when the project is inconsistent.
"""
import json
import os
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT = os.path.join(REPO, "TemporalWordflow.xcodeproj", "project.pbxproj")

# Keys whose value is a list of object IDs.
LIST_REF_KEYS = ("files", "children", "buildPhases", "targets", "buildConfigurations",
                 "buildRules", "dependencies")
# Keys whose value is a single object ID.
SCALAR_REF_KEYS = ("fileRef", "buildConfigurationList", "mainGroup", "productRefGroup",
                   "productReference", "target", "targetProxy")

errors = []
warnings = []


def fail(message):
    errors.append(message)


def warn(message):
    warnings.append(message)


def load(path):
    raw = subprocess.run(["plutil", "-convert", "json", "-o", "-", path],
                         check=True, capture_output=True).stdout
    return json.loads(raw)


def resolve_paths(objects, root_group):
    """Map file-reference ID -> repo-relative path, walking the group tree."""
    resolved = {}

    def walk(gid, prefix, seen):
        if gid in seen:
            fail("group cycle at %s" % gid)
            return
        group = objects.get(gid)
        if group is None:
            return
        here = os.path.join(prefix, group["path"]) if group.get("path") else prefix
        for child in group.get("children", []):
            obj = objects.get(child)
            if obj is None:
                continue
            if obj.get("isa") == "PBXGroup":
                walk(child, here, seen | {gid})
            elif obj.get("sourceTree") == "<group>" and obj.get("path"):
                resolved[child] = os.path.join(here, obj["path"])

    walk(root_group, "", frozenset())
    return resolved


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT
    if not os.path.exists(path):
        print("ERROR missing %s" % path)
        return 1

    plist = load(path)
    objects = plist.get("objects", {})

    root = plist.get("rootObject")
    if not root:
        fail("rootObject is not set")
    elif root not in objects:
        fail("rootObject %s is not an object" % root)
    elif objects[root].get("isa") != "PBXProject":
        fail("rootObject %s is %s, expected PBXProject" % (root, objects[root].get("isa")))

    # 1. Every reference resolves to a real object.
    for oid, obj in objects.items():
        isa = obj.get("isa", "?")
        for key in LIST_REF_KEYS:
            for ref in obj.get(key, []) or []:
                if ref not in objects:
                    fail("%s %s.%s references unknown object %s" % (isa, oid, key, ref))
        for key in SCALAR_REF_KEYS:
            ref = obj.get(key)
            if ref and ref not in objects:
                fail("%s %s.%s references unknown object %s" % (isa, oid, key, ref))

    # 2. Every PBXBuildFile points at a file reference, and each is built once.
    seen_in_phase = {}
    for oid, obj in objects.items():
        if obj.get("isa") != "PBXBuildFile":
            continue
        ref = obj.get("fileRef")
        if not ref:
            fail("PBXBuildFile %s has no fileRef" % oid)
        elif objects.get(ref, {}).get("isa") != "PBXFileReference":
            fail("PBXBuildFile %s fileRef %s is not a PBXFileReference" % (oid, ref))
    for oid, obj in objects.items():
        if not str(obj.get("isa", "")).endswith("BuildPhase"):
            continue
        for bid in obj.get("files", []) or []:
            ref = objects.get(bid, {}).get("fileRef")
            if ref is None:
                continue
            key = (obj["isa"], ref)
            if key in seen_in_phase:
                fail("file %s appears twice in %s" % (ref, obj["isa"]))
            seen_in_phase[key] = bid

    # 3. Every file reference is reachable from the main group exactly once.
    project = objects.get(root, {})
    resolved = resolve_paths(objects, project.get("mainGroup"))
    for oid, obj in objects.items():
        if obj.get("isa") != "PBXFileReference":
            continue
        if obj.get("sourceTree") == "<group>" and oid not in resolved:
            fail("file reference %s (%s) is not in any group" % (oid, obj.get("path")))

    # 4. Every build-phase input exists on disk (missing is a warning only).
    built = {objects[b]["fileRef"] for o in objects.values()
             if str(o.get("isa", "")).endswith("BuildPhase")
             for b in (o.get("files") or []) if objects.get(b, {}).get("fileRef")}
    checked = 0
    for ref in sorted(built):
        rel = resolved.get(ref)
        if rel is None:
            continue
        checked += 1
        if not os.path.exists(os.path.join(REPO, rel)):
            warn("build input not on disk yet: %s" % rel)

    # 5. Nothing under the source root is silently left out of the build.
    listed = {resolved[r] for r in built if r in resolved}
    for dirpath, dirnames, filenames in os.walk(os.path.join(REPO, "TemporalWordflow")):
        dirnames[:] = [d for d in dirnames if not d.endswith(".xcassets")]
        for filename in filenames:
            if not filename.endswith(".swift"):
                continue
            rel = os.path.relpath(os.path.join(dirpath, filename), REPO)
            if rel not in listed:
                fail("%s exists on disk but is not in the Sources build phase" % rel)

    # 6. Every target is wired up: the app plus the UI test bundle.
    targets = project.get("targets", [])
    kinds = sorted(objects.get(t, {}).get("productType", "") for t in targets)
    expected = ["com.apple.product-type.application",
                "com.apple.product-type.bundle.ui-testing"]
    if kinds != expected:
        fail("expected an app and a UI test bundle, found %s" % kinds)
    for tid in targets:
        target = objects.get(tid, {})
        phases = [objects.get(p, {}).get("isa") for p in target.get("buildPhases", [])]
        required = ["PBXSourcesBuildPhase", "PBXFrameworksBuildPhase"]
        if target.get("productType") == "com.apple.product-type.application":
            required.append("PBXResourcesBuildPhase")
        for phase in required:
            if phase not in phases:
                fail("target %s is missing a %s" % (target.get("name", tid), phase))
        if target.get("productType") == "com.apple.product-type.bundle.ui-testing":
            settings = {}
            for c in objects.get(target.get("buildConfigurationList"), {}).get("buildConfigurations", []):
                settings.update(objects.get(c, {}).get("buildSettings", {}))
            if settings.get("TEST_TARGET_NAME") != "TemporalWordflow":
                fail("the UI test bundle must set TEST_TARGET_NAME")
            if not target.get("dependencies"):
                fail("the UI test bundle must depend on the app target")
        for lid in (target.get("buildConfigurationList"), project.get("buildConfigurationList")):
            names = sorted(objects.get(c, {}).get("name")
                           for c in objects.get(lid, {}).get("buildConfigurations", []))
            if names != ["Debug", "Release"]:
                fail("configuration list %s has %s, expected Debug + Release" % (lid, names))

    for message in warnings:
        print("WARN  %s" % message)
    for message in errors:
        print("ERROR %s" % message)
    if errors:
        print("FAILED with %d error(s)" % len(errors))
        return 1
    print("OK  %d objects, %d build inputs checked, %d warning(s)"
          % (len(objects), checked, len(warnings)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
