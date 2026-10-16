#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
python3 - <<'PY'
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("cf", "actions/curseforge-publish/publish.py")
cf = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cf)

VERSIONS = [
    {"id": 16984, "name": "12.1.5", "slug": "12-1-5", "gameVersionTypeID": 10},
    {"id": 99999, "name": "12.1.5", "slug": "12-1-5", "gameVersionTypeID": 20},
    {"id": 17053, "name": "1.60.1", "slug": "1-60-1", "gameVersionTypeID": 20},
]
TYPES = [
    {"id": 10, "name": "Retail", "slug": "retail"},
    {"id": 20, "name": "Classic", "slug": "classic"},
]

class Tests(unittest.TestCase):
    def lookup(self, url, token):
        return TYPES if url.endswith("/version-types") else VERSIONS

    def test_resolution_and_ambiguity(self):
        with patch.object(cf, "request_json", side_effect=self.lookup):
            self.assertEqual(cf.resolve_version("https://wow.curseforge.com", "secret", "12.1.5", "retail"), 16984)
            self.assertEqual(cf.resolve_version("https://wow.curseforge.com", "secret", "12-1-5", "10"), 16984)
            self.assertEqual(cf.resolve_version("https://wow.curseforge.com", "secret", "1.60.1", "classic"), 17053)
            with self.assertRaisesRegex(cf.PublicationError, "matched 2"):
                cf.resolve_version("https://wow.curseforge.com", "secret", "12.1.5", "")
            with self.assertRaisesRegex(cf.PublicationError, "matched 0"):
                cf.resolve_version("https://wow.curseforge.com", "secret", "12.1.6", "retail")
            with self.assertRaisesRegex(cf.PublicationError, "Version type"):
                cf.resolve_version("https://wow.curseforge.com", "secret", "12.1.5", "unknown")

    def environment(self, artifact, output):
        return {
            "CURSEFORGE_TOKEN": "secret", "CF_PROJECT_ID": "123", "CF_GAME": "wow",
            "CF_GAME_VERSION": "12.1.5", "CF_GAME_VERSION_TYPE": "retail",
            "CF_FILE": str(artifact), "CF_RELEASE_TYPE": "beta",
            "CF_CHANGELOG_TYPE": "markdown", "CF_CHANGELOG": "Hello",
            "CF_DISPLAY_NAME": "My addon", "GITHUB_OUTPUT": str(output),
        }

    def test_upload_contract_and_output(self):
        with tempfile.TemporaryDirectory() as directory:
            artifact = Path(directory) / "addon.zip"
            artifact.write_bytes(b"sample zip contents")
            output = Path(directory) / "output"
            env = self.environment(artifact, output)
            def fake_upload(base, token, project, file, metadata):
                self.assertEqual(base, "https://wow.curseforge.com")
                self.assertEqual((project, metadata["gameVersions"]), (123, [16984]))
                self.assertEqual(metadata["releaseType"], "beta")
                self.assertEqual(metadata["changelog"], "Hello")
                self.assertEqual(metadata["displayName"], "My addon")
                body, content_type = cf.make_multipart(metadata, file)
                self.assertIn(b"sample zip contents", body)
                self.assertIn(b'name="metadata"', body)
                self.assertIn(b'name="file"', body)
                self.assertTrue(content_type.startswith("multipart/form-data; boundary="))
                return 777
            with patch.object(cf, "request_json", side_effect=self.lookup), patch.object(cf, "publish", side_effect=fake_upload):
                self.assertEqual(cf.run(env), (16984, 777))
            self.assertIn("game-version-id=16984", output.read_text())
            self.assertIn("file-id=777", output.read_text())

    def test_dry_run_and_override(self):
        with tempfile.TemporaryDirectory() as directory:
            artifact = Path(directory) / "addon.zip"
            artifact.write_bytes(b"x")
            output = Path(directory) / "output"
            env = self.environment(artifact, output)
            env.update(CF_DRY_RUN="true", CF_GAME_VERSION_ID="16984")
            with patch.object(cf, "request_json", side_effect=AssertionError("should not discover")), patch.object(cf, "publish", side_effect=AssertionError("should not publish")):
                self.assertEqual(cf.run(env), (16984, None))
            self.assertIn("file-id=\n", output.read_text())

    def test_validation(self):
        with tempfile.TemporaryDirectory() as directory:
            artifact = Path(directory) / "addon.zip"
            artifact.write_bytes(b"x")
            env = self.environment(artifact, Path(directory) / "out")
            for key, value in (("CF_GAME", "../oops"), ("CF_PROJECT_ID", "0"),
                               ("CF_RELEASE_TYPE", "stable"), ("CF_DRY_RUN", "maybe"),
                               ("CF_FILE", "/does-not-exist")):
                invalid = dict(env)
                invalid[key] = value
                with self.subTest(key=key), self.assertRaises(cf.PublicationError):
                    cf.run(invalid)

    def test_http_failure_is_not_retried(self):
        import urllib.error
        request = __import__("urllib.request", fromlist=["Request"]).Request("https://wow.curseforge.com/api/game/versions")
        with patch.object(cf.urllib.request, "urlopen", side_effect=urllib.error.HTTPError(request.full_url, 503, "busy", {}, None)) as call:
            with self.assertRaisesRegex(cf.PublicationError, "HTTP 503"):
                cf.fetch_json(request)
            self.assertEqual(call.call_count, 1)

unittest.main()
PY
