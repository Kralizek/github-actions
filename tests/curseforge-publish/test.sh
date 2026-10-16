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
                header, footer, content_type = cf.multipart_parts(metadata, file)
                self.assertIn(b'name="metadata"', header)
                self.assertIn(b'name="file"', header)
                self.assertTrue(footer.endswith(b"--\r\n"))
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

    def test_minecraft_multi_tag_upload(self):
        with tempfile.TemporaryDirectory() as directory:
            artifact = Path(directory) / "mod.jar"
            artifact.write_bytes(b"compiled mod")
            env = self.environment(artifact, Path(directory) / "out")
            env["CF_GAME"] = "minecraft"
            env["CF_GAME_VERSION"] = ""
            env["CF_GAME_VERSION_TYPE"] = ""
            env["CF_GAME_VERSIONS"] = json.dumps([
                {"version": "1.21.1", "type": "Minecraft 1.21"},
                {"version": "Fabric"}, {"version": "Java 21"},
                {"version": "Server"}
            ])
            env["CF_RELATIONS"] = json.dumps([{"slug": "fabric-api", "type": "requiredDependency"}])
            env["CF_MANUAL_RELEASE"] = "true"
            mapping = {"1.21.1": 111, "Fabric": 222, "Java 21": 333, "Server": 444}
            def fake_resolve(base, token, version, version_type):
                self.assertEqual(base, "https://minecraft.curseforge.com")
                if version == "1.21.1":
                    self.assertEqual(version_type, "Minecraft 1.21")
                return mapping[version]
            def fake_publish(base, token, project_id, file, metadata):
                self.assertEqual(metadata["gameVersions"], [111, 222, 333, 444])
                self.assertEqual(metadata["relations"]["projects"][0]["slug"], "fabric-api")
                self.assertTrue(metadata["isMarkedForManualRelease"])
                return 987
            with patch.object(cf, "resolve_version", side_effect=fake_resolve), patch.object(cf, "publish", side_effect=fake_publish):
                self.assertEqual(cf.run(env), (111, 987))
            self.assertIn("game-version-ids=111,222,333,444", Path(env["GITHUB_OUTPUT"]).read_text())

    def test_additional_file_and_invalid_combination(self):
        with tempfile.TemporaryDirectory() as directory:
            artifact = Path(directory) / "server.zip"
            artifact.write_bytes(b"server")
            env = self.environment(artifact, Path(directory) / "out")
            env.update(CF_GAME="kerbal", CF_GAME_VERSION="", CF_GAME_VERSION_TYPE="", CF_GAME_VERSIONS="[]",
                       CF_PARENT_FILE_ID="4321")
            with patch.object(cf, "publish", side_effect=lambda base, token, project, file, metadata:
                              (self.assertEqual(metadata["parentFileID"], 4321) or 777)):
                self.assertEqual(cf.run(env), (None, 777))
            env["CF_GAME_VERSION"] = "1.0"
            with self.assertRaisesRegex(cf.PublicationError, "does not support gameVersions"):
                cf.run(env)

    def test_duplicate_versions_are_deduplicated(self):
        with tempfile.TemporaryDirectory() as directory:
            artifact = Path(directory) / "mod.jar"
            artifact.write_bytes(b"jar")
            env = self.environment(artifact, Path(directory) / "out")
            env["CF_GAME_VERSION"] = ""
            env["CF_GAME_VERSION_TYPE"] = ""
            env["CF_GAME_VERSIONS"] = '[{"id":16984},"12.1.5"]'
            with patch.object(cf, "resolve_version", return_value=16984), patch.object(cf, "publish", return_value=777):
                self.assertEqual(cf.run(env), (16984, 777))
            self.assertIn("game-version-ids=16984", Path(env["GITHUB_OUTPUT"]).read_text())

    def test_orphan_version_type_is_rejected_before_io(self):
        with tempfile.TemporaryDirectory() as directory:
            artifact = Path(directory) / "mod.jar"
            artifact.write_bytes(b"jar")
            baseline = self.environment(artifact, Path(directory) / "out")
            for changes in (
                {"CF_GAME_VERSION": "", "CF_GAME_VERSION_TYPE": "retail"},
                {"CF_GAME_VERSION": "", "CF_GAME_VERSION_TYPE": "retail",
                 "CF_GAME_VERSIONS": '["Fabric"]'},
                {"CF_GAME_VERSION": "", "CF_GAME_VERSION_TYPE": "retail",
                 "CF_GAME_VERSION_NAMES": '["Client"]'},
                {"CF_GAME_VERSION": "", "CF_GAME_VERSION_TYPE": "retail",
                 "CF_PARENT_FILE_ID": "42"},
                {"CF_GAME_VERSION": "", "CF_GAME_VERSION_TYPE": "retail",
                 "CF_GAME_VERSION_ID": "16984"},
            ):
                env = dict(baseline)
                env.update(changes)
                with self.subTest(changes=changes), patch.object(
                    cf, "resolve_version", side_effect=AssertionError("must not resolve")
                ), patch.object(
                    cf, "publish", side_effect=AssertionError("must not publish")
                ):
                    with self.assertRaisesRegex(cf.PublicationError, "requires CF_GAME_VERSION"):
                        cf.run(env)

    def test_singular_plural_mutual_exclusion(self):
        with tempfile.TemporaryDirectory() as directory:
            artifact = Path(directory) / "mod.jar"
            artifact.write_bytes(b"jar")
            env = self.environment(artifact, Path(directory) / "out")
            env["CF_GAME_VERSIONS"] = '["Fabric"]'
            with patch.object(cf, "resolve_version", side_effect=AssertionError("must fail before lookup")):
                with self.assertRaisesRegex(cf.PublicationError, "mutually exclusive"):
                    cf.run(env)
            env["CF_GAME_VERSION"] = ""
            env["CF_GAME_VERSION_TYPE"] = ""
            env["CF_GAME_VERSION_ID"] = "42"
            with self.assertRaisesRegex(cf.PublicationError, "mutually exclusive"):
                cf.run(env)

    def test_malformed_multi_tag_inputs(self):
        with tempfile.TemporaryDirectory() as directory:
            artifact = Path(directory) / "mod.jar"
            artifact.write_bytes(b"jar")
            env = self.environment(artifact, Path(directory) / "out")
            for key, value in (("CF_GAME_VERSIONS", "{}"),
                               ("CF_GAME_VERSIONS", '[{"unexpected":"value"}]'),
                               ("CF_GAME_VERSIONS", '[{}]'),
                               ("CF_RELATIONS", '[{"slug":"foo","type":"invalid"}]'),
                               ("CF_MANUAL_RELEASE", "maybe")):
                invalid = dict(env)
                invalid[key] = value
                with self.subTest(key=key), self.assertRaises(cf.PublicationError):
                    cf.run(invalid)

    def test_native_version_names_without_discovery(self):
        with tempfile.TemporaryDirectory() as directory:
            artifact = Path(directory) / "mod.jar"
            artifact.write_bytes(b"jar")
            env = self.environment(artifact, Path(directory) / "out")
            env["CF_GAME_VERSION"] = ""
            env["CF_GAME_VERSION_TYPE"] = ""
            env["CF_GAME_VERSION_TYPE"] = ""
            env["CF_GAME_VERSION_NAMES"] = '["Client","Server","26.1.2","Client"]'
            def upload(base, token, project, file, metadata):
                self.assertEqual(metadata["gameVersionNames"], ["Client", "Server", "26.1.2"])
                self.assertNotIn("gameVersions", metadata)
                return 789
            with patch.object(cf, "request_json", side_effect=AssertionError("no lookup expected")), patch.object(cf, "publish", side_effect=upload):
                self.assertEqual(cf.run(env), (None, 789))
            self.assertIn("game-version-names=", Path(env["GITHUB_OUTPUT"]).read_text())

    def test_native_names_conflict_with_id_resolution(self):
        with tempfile.TemporaryDirectory() as directory:
            artifact = Path(directory) / "mod.jar"
            artifact.write_bytes(b"jar")
            env = self.environment(artifact, Path(directory) / "out")
            env["CF_GAME_VERSION_NAMES"] = '["Client"]'
            with self.assertRaisesRegex(cf.PublicationError, "mutually exclusive"):
                cf.run(env)
            env["CF_GAME_VERSION"] = ""
            env["CF_GAME_VERSION_TYPE"] = ""
            env["CF_GAME_VERSION_TYPE"] = "retail"
            with self.assertRaisesRegex(cf.PublicationError, "requires CF_GAME_VERSION"):
                cf.run(env)

    def test_streaming_upload_chunks(self):
        with tempfile.TemporaryDirectory() as directory:
            artifact = Path(directory) / "large-mod.jar"
            artifact.write_bytes(b"x" * (2 * 1024 * 1024 + 17))
            class FakeResponse:
                status = 200
                def read(self, n=-1):
                    return b'{"id":12345}'
            class FakeConnection:
                def __init__(self, *args, **kwargs):
                    self.headers = {}
                    self.sizes = []
                def putrequest(self, *args): pass
                def putheader(self, key, value): self.headers[key] = value
                def endheaders(self): pass
                def send(self, data): self.sizes.append(len(data))
                def getresponse(self): return FakeResponse()
                def close(self): pass
            connection = FakeConnection()
            with patch.object(cf.http.client, "HTTPSConnection", return_value=connection):
                self.assertEqual(cf.publish("https://minecraft.curseforge.com", "secret", 42, artifact, {"gameVersionNames": ["Client"]}), 12345)
            self.assertLessEqual(max(connection.sizes), 1024 * 1024)
            self.assertEqual(sum(connection.sizes), int(connection.headers["Content-Length"]))
            self.assertGreaterEqual(sum(1 for size in connection.sizes if size == 1024 * 1024), 2)

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
