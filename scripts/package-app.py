#!/usr/bin/env python3
"""Package a standalone SwiftPM build and sign Sparkle inside out."""
import base64
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
FEED = "https://github.com/ZipLyne-Agency/grove/releases/latest/download/appcast.xml"


def run(*args):
    subprocess.run([str(arg) for arg in args], check=True, timeout=120)


def main():
    binary = Path(sys.argv[1]).resolve(strict=True)
    output = Path(sys.argv[2]).expanduser().resolve()
    app = output / "Grove.app"
    if output == Path("/Applications") or app.is_symlink():
        raise SystemExit("Build into an artifact folder, then install the verified app separately.")
    output.mkdir(parents=True, exist_ok=True)
    config = json.loads((ROOT / "release/version.json").read_text())
    version = os.environ.get("GROVE_VERSION", config["version"])
    build = os.environ.get("GROVE_BUILD_NUMBER", config["build"])
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version) or not re.fullmatch(r"[1-9][0-9]*", build):
        raise SystemExit("Release version must be x.y.z and build must be a positive integer.")
    public_key = (ROOT / "release/sparkle-public-key.txt").read_text().strip()
    if len(base64.b64decode(public_key, validate=True)) != 32:
        raise SystemExit("Invalid Sparkle public key.")
    identity = os.environ.get("GROVE_SIGNING_IDENTITY", "-")
    team = os.environ.get("GROVE_TEAM_ID", "")
    profile = os.environ.get("GROVE_PROVISIONING_PROFILE", "")
    if identity != "-" and (not re.fullmatch(r"[A-Z0-9]{10}", team) or not Path(profile).is_file()):
        raise SystemExit("Developer ID builds require GROVE_TEAM_ID and GROVE_PROVISIONING_PROFILE.")
    framework = ROOT / ".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
    if not framework.is_dir():
        raise SystemExit("Sparkle framework missing. Run swift package resolve first.")
    with tempfile.TemporaryDirectory(prefix="grove-package-", dir=output) as temporary:
        bundle = Path(temporary) / "Grove.app"
        contents = bundle / "Contents"
        resources = contents / "Resources"
        (contents / "MacOS").mkdir(parents=True)
        resources.mkdir()
        shutil.copy2(ROOT / "LICENSE", resources / "Grove-LICENSE")
        shutil.copy2(ROOT / ".build/checkouts/Sparkle/LICENSE", resources / "Sparkle-LICENSE")
        (contents / "Frameworks").mkdir()
        shutil.copy2(binary, contents / "MacOS/Grove")
        embedded = contents / "Frameworks/Sparkle.framework"
        run("ditto", framework, embedded)
        info = {
            "CFBundleIdentifier": "agency.ziplyne.grove", "CFBundleName": "Grove",
            "CFBundleDisplayName": "Grove", "CFBundleExecutable": "Grove", "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": version, "CFBundleVersion": build,
            "LSMinimumSystemVersion": "15.0", "NSHighResolutionCapable": True,
            "CFBundleIconFile": "AppIcon", "NSHumanReadableCopyright": "Copyright © 2026 ZipLyne",
            "SUFeedURL": FEED, "SUPublicEDKey": public_key,
            "SURequireSignedFeed": True, "SUVerifyUpdateBeforeExtraction": True,
            "SUSignedFeedFailureExpirationInterval": 0,
            "SUEnableAutomaticChecks": True, "SUAutomaticallyUpdate": False,
            "SUEnableSystemProfiling": False, "SUSendProfileInfo": False,
        }
        (contents / "Info.plist").write_bytes(plistlib.dumps(info))
        iconset = Path(temporary) / "AppIcon.iconset"
        iconset.mkdir()
        original = Path(temporary) / "icon_1024.png"
        run("swift", ROOT / "scripts/make-icon.swift", original)
        for size in (16, 32, 128, 256, 512):
            for scale, suffix in ((1, ""), (2, "@2x")):
                run("sips", "-z", str(size * scale), str(size * scale), original,
                    "--out", iconset / f"icon_{size}x{size}{suffix}.png")
        run("iconutil", "-c", "icns", iconset, "-o", resources / "AppIcon.icns")

        def sign(path, preserve=False, entitlements=None):
            args = ["codesign", "--force", "--sign", identity]
            if identity != "-":
                args += ["--options", "runtime", "--timestamp"]
            if preserve:
                args += ["--preserve-metadata=entitlements"]
            if entitlements:
                args += ["--entitlements", str(entitlements)]
            run(*args, path)

        internal = embedded / "Versions/B"
        for name in ("Installer", "Downloader"):
            sign(internal / f"XPCServices/{name}.xpc", preserve=True)
        sign(internal / "Autoupdate", preserve=True)
        sign(internal / "Updater.app", preserve=True)
        sign(embedded)
        entitlements = None
        if identity != "-":
            shutil.copy2(profile, contents / "embedded.provisionprofile")
            entitlements = Path(temporary) / "Grove.entitlements.plist"
            entitlements.write_bytes(plistlib.dumps({
                "com.apple.application-identifier": team + ".agency.ziplyne.grove",
                "com.apple.developer.team-identifier": team,
            }))
        sign(bundle, entitlements=entitlements)
        run("codesign", "--verify", "--deep", "--strict", bundle)
        if app.exists():
            shutil.rmtree(app)
        shutil.move(str(bundle), app)
    print(f"Built {app} ({version}, build {build})")


if __name__ == "__main__":
    main()
