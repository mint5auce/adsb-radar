#!/usr/bin/env python3
"""Create bundle metadata from the checked-in release version."""

import argparse
import base64
import binascii
import json
import plistlib
import re
from pathlib import Path
from urllib.parse import urlsplit
from xml.etree import ElementTree


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=Path(__file__).resolve().parents[1] / "release.json")
    parser.add_argument("--configuration", choices=("debug", "release"), required=True)
    parser.add_argument("--distribution", action="store_true")
    parser.add_argument("--feed-url")
    parser.add_argument("--public-key")
    parser.add_argument("--tag", help="Validate that a release tag matches the manifest")
    parser.add_argument("--previous-appcast", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        release = json.loads(args.manifest.read_text())
        if not isinstance(release, dict) or not isinstance(release.get("version"), str) or not re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", release["version"]):
            raise ValueError("version must be a stable version such as 0.2.0")
        if type(release.get("build")) is not int or not 1 <= release["build"] <= 999999999:
            raise ValueError("build must be a positive integer no larger than 999999999")
        if args.tag is not None and args.tag != "v" + release["version"]:
            raise ValueError("release tag must match v" + release["version"])
        if args.previous_appcast:
            feed = ElementTree.parse(args.previous_appcast)
            previous_builds = [int(item.text) for item in feed.findall(".//{http://www.andymatuschak.org/xml-namespaces/sparkle}version")]
            if previous_builds and release["build"] <= max(previous_builds):
                raise ValueError("release build must be higher than every build in the previous appcast")
        if args.distribution:
            feed = urlsplit(args.feed_url or "")
            if feed.scheme != "https" or not feed.hostname or feed.username or feed.password or feed.fragment:
                raise ValueError("distribution requires a public HTTPS feed URL without credentials or a fragment")
            try:
                if len(base64.b64decode(args.public_key or "", validate=True)) != 32:
                    raise ValueError()
            except (ValueError, binascii.Error):
                raise ValueError("distribution requires a base64-encoded 32-byte Sparkle public key") from None
            if args.configuration != "release":
                raise ValueError("distribution requires the release configuration")
    except (OSError, ValueError, ElementTree.ParseError) as error:
        parser.error(str(error))
    info = {
        "CFBundleIdentifier": "dev.mint5auce.phosphor",
        "CFBundleExecutable": "Phosphor",
        "CFBundleName": "Phosphor",
        "CFBundleDisplayName": "Phosphor",
        "CFBundleIconFile": "AppIcon.icns",
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": release["version"],
        "CFBundleVersion": str(release["build"]),
        "LSMinimumSystemVersion": "14.0",
        "NSHighResolutionCapable": True,
        "NSQuitAlwaysKeepsWindows": False,
        "PhosphorUpdatesEnabled": args.distribution,
    }
    if args.distribution:
        info.update({
            "SUFeedURL": args.feed_url,
            "SUPublicEDKey": args.public_key,
            "SUVerifyUpdateBeforeExtraction": True,
            "SURequireSignedFeed": True,
            "SUEnableSystemProfiling": False,
            "SUAutomaticallyUpdate": False,
            "SUScheduledCheckInterval": 86400,
        })
    args.output.write_bytes(plistlib.dumps(info))


if __name__ == "__main__":
    main()
