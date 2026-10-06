#!/usr/bin/env python3
"""Validate and publish GitHub releases without replacing published artifacts."""

import argparse
import hashlib
import json
import re
import subprocess
import tempfile
from pathlib import Path


def gh(*arguments):
    return subprocess.check_output(["gh", *arguments], text=True)


def preflight(repository, release, allow_existing=False):
    pages = json.loads(gh("api", "--paginate", "--slurp", f"repos/{repository}/releases"))
    version = tuple(map(int, release["version"].split(".")))
    tag = "v" + release["version"]
    for previous in [item for page in pages for item in page]:
        if previous["draft"] or previous["prerelease"]:
            continue
        if allow_existing and previous["tag_name"] == tag:
            continue
        match = re.fullmatch(r"v([0-9]+)\.([0-9]+)\.([0-9]+)", previous["tag_name"])
        if match and tuple(map(int, match.groups())) >= version:
            raise ValueError(f"{tag} must be newer than published release {previous['tag_name']}")
        build = re.search(r"<!-- phosphor-build:([0-9]+) -->", previous["body"] or "")
        if match and not build:
            raise ValueError(f"Published release {previous['tag_name']} has no build record; reconcile it before releasing")
        if build and int(build[1]) >= release["build"]:
            raise ValueError("Release build must be higher than all published builds, including withdrawn updates")
    return tag


def publish(repository, directory, release, source_sha):
    if not source_sha or not re.fullmatch(r"[0-9a-f]{40}", source_sha):
        raise ValueError("Publication requires the prepared source commit via --source-sha")
    tag = "v" + release["version"]
    target = json.loads(gh("api", f"repos/{repository}/git/ref/tags/{tag}"))["object"]
    for _ in range(8):
        if target["type"] != "tag":
            break
        target = json.loads(gh("api", f"repos/{repository}/git/tags/{target['sha']}"))["object"]
    if target["type"] != "commit" or target["sha"] != source_sha:
        raise ValueError("Release tag no longer points to the prepared source commit")
    tag = preflight(repository, release, allow_existing=True)
    archive = directory / f"Phosphor-{release['version']}.zip"
    notes = directory / f"Phosphor-{release['version']}.md"
    for artifact in (archive, notes, directory / "appcast.xml"):
        if not artifact.is_file() or not artifact.stat().st_size:
            raise ValueError(f"Release artifact missing: {artifact}")
    releases = json.loads(gh("api", "--paginate", "--slurp", f"repos/{repository}/releases"))
    existing = next((item for page in releases for item in page if item["tag_name"] == tag), None)
    if existing and existing["prerelease"]:
        raise ValueError("A prerelease already uses this stable release tag; use a new version")
    body = notes.read_text() + f"\n<!-- phosphor-build:{release['build']} -->\n"
    with tempfile.TemporaryDirectory() as temporary:
        body_file = Path(temporary) / "notes.md"
        body_file.write_text(body)
        if existing:
            if existing["body"] != body:
                raise ValueError("Existing release does not match the prepared release; use a new version")
        else:
            gh("release", "create", tag, "--repo", repository, "--verify-tag", "--draft",
               "--title", f"Phosphor {release['version']}", "--notes-file", str(body_file))
        for artifact in (archive, directory / "release.json", directory / "appcast.xml"):
            if existing and any(asset["name"] == artifact.name for asset in existing["assets"]):
                downloaded = Path(temporary) / artifact.name
                gh("release", "download", tag, "--repo", repository, "--pattern", artifact.name, "--dir", temporary)
                if hashlib.sha256(downloaded.read_bytes()).digest() != hashlib.sha256(artifact.read_bytes()).digest():
                    raise ValueError(f"Existing asset differs: {artifact.name}; use a new version")
            else:
                if existing and not existing["draft"]:
                    raise ValueError(f"Published release is missing {artifact.name}; use a new version")
                gh("release", "upload", tag, str(artifact), "--repo", repository)
        if not existing or existing["draft"]:
            gh("release", "edit", tag, "--repo", repository, "--draft=false", "--latest")
        downloaded = Path(temporary) / "public.zip"
        subprocess.run(["curl", "--fail", "--location", "--retry", "3", "--silent", "--show-error",
                        f"https://github.com/{repository}/releases/download/{tag}/{archive.name}",
                        "--output", str(downloaded)], check=True)
        if hashlib.sha256(downloaded.read_bytes()).digest() != hashlib.sha256(archive.read_bytes()).digest():
            raise ValueError("Public download differs from prepared archive; update feed must not be deployed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("preflight", "publish"))
    parser.add_argument("--repository", required=True)
    parser.add_argument("--directory", type=Path, default=Path("build/release-assets"))
    parser.add_argument("--source-sha", help="Source commit used to prepare the candidate")
    args = parser.parse_args()
    manifest = Path("release.json") if args.action == "preflight" else args.directory / "release.json"
    try:
        release = json.loads(manifest.read_text())
        if args.action == "preflight":
            preflight(args.repository, release)
        else:
            publish(args.repository, args.directory, release, args.source_sha)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Release failed: {error}\n")


if __name__ == "__main__":
    main()
