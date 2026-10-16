#!/usr/bin/env python3
"""Publish a prebuilt artifact through the CurseForge project upload API.

No implicit retry: an interrupted upload may already have succeeded.
"""
import json
import os
from pathlib import Path
import re
import sys
import urllib.error
import urllib.request
import uuid


class PublicationError(Exception):
    pass


def required(env, name):
    value = env.get(name, "").strip()
    if not value:
        raise PublicationError(f"{name} is required")
    return value


def positive_id(value, name):
    if not re.fullmatch(r"[0-9]+", value or "") or int(value) <= 0:
        raise PublicationError(f"{name} must be a positive integer")
    return int(value)


def request_json(url, token):
    request = urllib.request.Request(url, headers={
        "X-Api-Token": token, "Accept": "application/json",
    })
    return fetch_json(request)


def fetch_json(request):
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        raise PublicationError(f"CurseForge HTTP {error.code} at {request.full_url}") from error
    except (urllib.error.URLError, TimeoutError) as error:
        raise PublicationError(f"CurseForge request failed at {request.full_url}: {error}") from error
    except (ValueError, UnicodeError) as error:
        raise PublicationError("CurseForge returned invalid JSON") from error


def exact(value, candidate):
    return isinstance(candidate, str) and candidate.casefold() == value.casefold()


def resolve_version(base, token, version, version_type):
    versions = request_json(base + "/api/game/versions", token)
    if not isinstance(versions, list):
        raise PublicationError("Unexpected CurseForge versions response")
    candidates = [row for row in versions if isinstance(row, dict) and
                  (exact(version, row.get("name")) or exact(version, row.get("slug")))]
    if version_type:
        types = request_json(base + "/api/game/version-types", token)
        if not isinstance(types, list):
            raise PublicationError("Unexpected CurseForge version types response")
        matches = [row for row in types if isinstance(row, dict) and
                   (exact(version_type, row.get("name")) or exact(version_type, row.get("slug")) or
                    (str(row.get("id")) == version_type and row.get("id") is not None))]
        if len(matches) != 1:
            raise PublicationError(f"Version type {version_type!r} matched {len(matches)} entries; expected one")
        type_id = matches[0].get("id")
        candidates = [row for row in candidates if row.get("gameVersionTypeID") == type_id]
    if len(candidates) != 1:
        details = ", ".join(f"{row.get('name')} (id={row.get('id')}, type={row.get('gameVersionTypeID')})"
                            for row in candidates[:12])
        raise PublicationError(
            f"Version {version!r} ({version_type or 'any type'}) matched {len(candidates)} "
            f"entries; expected exactly one. Candidates: {details}")
    return positive_id(str(candidates[0].get("id", "")), "resolved game version ID")


def make_multipart(metadata, artifact):
    boundary = "curseforge-" + uuid.uuid4().hex
    filename = artifact.name.replace('"', "").replace("\r", "").replace("\n", "")
    parts = [
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"metadata\"\r\n\r\n".encode(),
        json.dumps(metadata, ensure_ascii=False).encode(),
        b"\r\n",
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"{filename}\"\r\nContent-Type: application/zip\r\n\r\n".encode(),
        artifact.read_bytes(),
        b"\r\n",
        f"--{boundary}--\r\n".encode(),
    ]
    return b"".join(parts), f"multipart/form-data; boundary={boundary}"


def publish(base, token, project_id, artifact, metadata):
    body, content_type = make_multipart(metadata, artifact)
    request = urllib.request.Request(
        f"{base}/api/projects/{project_id}/upload-file",
        data=body,
        method="POST",
        headers={"X-Api-Token": token, "Accept": "application/json",
                 "Content-Type": content_type},
    )
    result = fetch_json(request)
    if not isinstance(result, dict):
        raise PublicationError("Unexpected upload response")
    return positive_id(str(result.get("id", "")), "uploaded file ID")


def run(env):
    token = required(env, "CURSEFORGE_TOKEN")
    game = required(env, "CF_GAME")
    if not re.fullmatch(r"[a-z0-9-]+", game):
        raise PublicationError("CF_GAME must be a CurseForge endpoint slug")
    project_id = positive_id(required(env, "CF_PROJECT_ID"), "CF_PROJECT_ID")
    version = required(env, "CF_GAME_VERSION")
    release_type = required(env, "CF_RELEASE_TYPE")
    if release_type not in ("alpha", "beta", "release"):
        raise PublicationError("CF_RELEASE_TYPE must be alpha, beta, or release")
    changelog_type = env.get("CF_CHANGELOG_TYPE", "markdown")
    if changelog_type not in ("text", "html", "markdown"):
        raise PublicationError("CF_CHANGELOG_TYPE must be text, html, or markdown")
    dry_run = env.get("CF_DRY_RUN", "false").lower()
    if dry_run not in ("true", "false"):
        raise PublicationError("CF_DRY_RUN must be true or false")
    artifact = Path(required(env, "CF_FILE"))
    if not artifact.is_file() or not artifact.stat().st_size:
        raise PublicationError("CF_FILE must refer to a nonempty regular file")
    if env.get("CF_GAME_VERSION_ID", "").strip():
        version_id = positive_id(env["CF_GAME_VERSION_ID"].strip(), "CF_GAME_VERSION_ID")
    else:
        version_id = resolve_version(
            f"https://{game}.curseforge.com", token, version, env.get("CF_GAME_VERSION_TYPE", "").strip()
        )
    file_id = None
    if dry_run != "true":
        metadata = {
            "gameVersions": [version_id],
            "releaseType": release_type,
            "changelog": env.get("CF_CHANGELOG", ""),
            "changelogType": changelog_type,
        }
        if env.get("CF_DISPLAY_NAME", ""):
            metadata["displayName"] = env["CF_DISPLAY_NAME"]
        file_id = publish(f"https://{game}.curseforge.com", token, project_id, artifact, metadata)
    output = env.get("GITHUB_OUTPUT")
    if output:
        with open(output, "a", encoding="utf-8") as file:
            file.write(f"game-version-id={version_id}\n")
            file.write(f"file-id={file_id or ''}\n")
    print(f"CurseForge game version ID: {version_id}")
    print("Dry run: no file uploaded" if file_id is None else f"CurseForge file ID: {file_id}")
    return version_id, file_id


if __name__ == "__main__":
    try:
        run(os.environ)
    except (PublicationError, OSError) as exc:
        print(f"::error::{exc}", file=sys.stderr)
        sys.exit(1)
