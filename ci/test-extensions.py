#!/usr/bin/env python3
"""Download released VSIXs on the runner, or smoke-test them in the built image."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import urllib.request
import zipfile

REPOSITORIES = ("eoap-validator-vscode", "cwl-metadata-editor", "cwl-uml-viewer")


def run(*args, **kwargs):
    print("+", " ".join(map(str, args)), flush=True)
    try:
        return subprocess.run(list(map(str, args)), check=True, timeout=600, **kwargs)
    except subprocess.CalledProcessError as error:
        if error.stdout:
            print(error.stdout, flush=True)
        if error.stderr:
            print(error.stderr, flush=True)
        raise


def download(destination):
    destination.mkdir(parents=True, exist_ok=True)
    for repo in REPOSITORIES:
        headers = {"Accept": "application/vnd.github+json"}
        if os.environ.get("GITHUB_TOKEN"):
            headers["Authorization"] = "Bearer " + os.environ["GITHUB_TOKEN"]
        request = urllib.request.Request(
            f"https://api.github.com/repos/eoap/{repo}/releases/latest", headers=headers
        )
        with urllib.request.urlopen(request, timeout=60) as response:
            release = json.load(response)
        assets = [a for a in release["assets"] if a["name"].endswith(".vsix")]
        if len(assets) != 1:
            raise RuntimeError(f"{repo}: expected one VSIX, found {len(assets)}")
        print(f"{repo}: {release['tag_name']} ({assets[0]['name']})", flush=True)
        # Do not forward the API token to release asset download hosts.
        with urllib.request.urlopen(assets[0]["browser_download_url"], timeout=120) as response:
            (destination / f"{repo}.vsix").write_bytes(response.read())
        (destination / f"{repo}.release.json").write_text(json.dumps({
            "tag": release["tag_name"], "url": assets[0]["browser_download_url"]
        }, indent=2) + "\n")


def test(source):
    with tempfile.TemporaryDirectory(prefix="extension-smoke-") as temporary:
        root = Path(temporary)
        extensions = root / "extensions"
        user_data = root / "user-data"
        cli = ("code-server", "--extensions-dir", extensions, "--user-data-dir", user_data)
        installed = {}
        for repo in REPOSITORIES:
            vsix = source / f"{repo}.vsix"
            with zipfile.ZipFile(vsix) as archive:
                manifest = json.loads(archive.read("extension/package.json"))
            identifier = f"{manifest['publisher']}.{manifest['name']}"
            print(f"Installing {identifier}@{manifest['version']}; VS Code {manifest['engines']['vscode']}", flush=True)
            # No --force: incompatible VS Code engines must fail installation.
            run(*cli, "--install-extension", vsix)
            installed[repo] = (identifier, manifest["version"])
        listed = run(*cli, "--list-extensions", "--show-versions", capture_output=True, text=True).stdout
        print(listed, flush=True)
        for identifier, version in installed.values():
            if f"{identifier}@{version}".lower() not in listed.lower().splitlines():
                raise RuntimeError(f"Extension missing after installation: {identifier}@{version}")

        def extension_path(repo):
            identifier, version = installed[repo]
            matches = list(extensions.glob(f"{identifier}-{version}*"))
            if len(matches) != 1:
                raise RuntimeError(f"Cannot locate installed {identifier}: {matches}")
            return matches[0]

        run("python3", "-m", "pip", "check")
        # Exercise the validator's default first-use venv and bundled wheel.
        validator = extension_path("eoap-validator-vscode")
        wheels = list((validator / "vendor").glob("eoap_validator-*.whl"))
        if len(wheels) != 1:
            raise RuntimeError(f"Expected one bundled validator wheel: {wheels}")
        venv = root / "validator-venv"
        run("python3", "-m", "venv", venv)
        python = venv / "bin/python"
        run(python, "-m", "pip", "install", "--disable-pip-version-check", wheels[0])
        run(python, "-m", "pip", "check")
        run(python, "-m", "eoap_validator", "--help")

        # Use the installed bridge exactly as the extension does, including its
        # vendored sys.path and isolated Python mode. Global imports are insufficient.
        uml = extension_path("cwl-uml-viewer")
        fixture = uml / "examples/echo.cwl"
        request = {"path": str(fixture), "text": fixture.read_text()}

        def bridge(extra):
            result = run("python3", "-I", uml / "python/bridge.py",
                         input=json.dumps(request | extra), capture_output=True, text=True)
            payload = json.loads(result.stdout)
            if "error" in payload:
                raise RuntimeError(payload["error"])
            return payload

        info = bridge({"action": "inspect"})
        if not info["workflows"] or not info["diagrams"]:
            raise RuntimeError(f"No UML workflows or diagrams: {info}")
        jars = list((uml / "vendor").glob("plantuml-asl-*.jar"))
        if len(jars) != 1:
            raise RuntimeError(f"Expected one bundled PlantUML renderer: {jars}")
        for diagram in info["diagrams"]:
            puml = bridge({"action": "render", "diagram": diagram,
                           "workflow": info["workflows"][0]})["puml"]
            svg = run("java", "-Djava.awt.headless=true",
                      "-DPLANTUML_SECURITY_PROFILE=SANDBOX", "-jar", jars[0],
                      "-pipe", "-charset", "UTF-8", "-tsvg", "-failfast2",
                      input=puml, capture_output=True, text=True).stdout
            if "<svg" not in svg:
                raise RuntimeError(f"No SVG rendered for {diagram}")
            print(f"Rendered {diagram} successfully", flush=True)
        print("All released extensions installed and runtime smoke checks passed.", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("download", "test"))
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    if args.mode == "download":
        download(args.directory.resolve())
    else:
        test(args.directory.resolve())
