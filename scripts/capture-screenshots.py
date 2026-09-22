#!/usr/bin/env python3
"""Build the signed app with demo data and capture settings, run capture recipes, and export attachments."""
import argparse
import datetime
import json
import pathlib
import subprocess
import shutil


def run(*args):
    subprocess.run(args, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--destination", default="platform=macOS,arch=arm64",
                        help="An xcodebuild destination, including a simulator ID for iOS")
    parser.add_argument("--output", type=pathlib.Path, help="New directory for results and PNGs")
    options = parser.parse_args()
    root = pathlib.Path(__file__).resolve().parent.parent
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    output = (options.output or root / ".build" / "screenshots" / stamp).resolve()
    output.mkdir(parents=True, exist_ok=False)
    result = output / "capture.xcresult"
    exports = output / "attachments"
    # This directory is never used for unsigned unit tests.
    derived = root / ".build" / "screenshot-capture-signed"
    metadata = {"destination": options.destination, "created": stamp,
                "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True).strip(),
                "revision": subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip(),
                "workingTreeChanges": subprocess.check_output(["git", "-C", str(root), "status", "--porcelain"], text=True)}
    (output / "capture.json").write_text(json.dumps(metadata, indent=2) + "\n")
    simulator_id = next((part[3:] for part in options.destination.split(",") if part.startswith("id=")), None)
    simulator = "iOS Simulator" in options.destination
    if simulator and not simulator_id:
        parser.error("Use platform=iOS Simulator,id=<UDID> so status-bar normalization targets the correct device.")
    try:
        if simulator:
            run("xcrun", "simctl", "status_bar", simulator_id, "override", "--time", "9:41",
                "--dataNetwork", "wifi", "--wifiMode", "active", "--wifiBars", "3",
                "--batteryState", "charged", "--batteryLevel", "100")
        run("xcodebuild", "-project", str(root / "BitDream.xcodeproj"), "-scheme", "BitDreamDemo",
            "-configuration", "Debug", "-destination", options.destination, "-derivedDataPath", str(derived),
            "-resultBundlePath", str(result), "-parallel-testing-enabled", "NO", "-collect-test-diagnostics", "never", "test")
        run("xcrun", "xcresulttool", "export", "attachments", "--path", str(result), "--output-path", str(exports))
    finally:
        if simulator:
            run("xcrun", "simctl", "status_bar", simulator_id, "clear")
    manifest = json.loads((exports / "manifest.json").read_text())
    captures = []
    for test in manifest:
        for attachment in test["attachments"]:
            name = attachment["suggestedHumanReadableName"]
            if name.startswith(("library-", "detail-", "files-", "peers-")):
                captures.append(attachment)
    expected = {f"{view}-{appearance}" for view in ("library", "detail", "files", "peers")
                for appearance in ("light", "dark")}
    names = [capture["suggestedHumanReadableName"].split("_", 1)[0] for capture in captures]
    if len(names) != len(expected) or set(names) != expected:
        raise RuntimeError(f"Capture attachments did not match {sorted(expected)}: {names}. Inspect {exports}")
    for capture in captures:
        filename = capture["suggestedHumanReadableName"].split("_", 1)[0] + ".png"
        shutil.copyfile(exports / capture["exportedFileName"], output / filename)
    print(f"Screenshots and capture metadata: {output}")


if __name__ == "__main__":
    main()
