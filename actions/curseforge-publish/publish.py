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


def parse_version_selectors(env):
    try:
        extra = json.loads(env.get("CF_GAME_VERSIONS", "[]"))
    except ValueError as exc:
        raise PublicationError("CF_GAME_VERSIONS must be a JSON array") from exc
    if not isinstance(extra, list):
        raise PublicationError("CF_GAME_VERSIONS must be a JSON array")
    selectors = []
    primary_version = env.get("CF_GAME_VERSION", "").strip()
    primary_id = env.get("CF_GAME_VERSION_ID", "").strip()
    if primary_version or primary_id:
        selectors.append({"version": primary_version, "type": env.get("CF_GAME_VERSION_TYPE", "").strip(),
                          "id": primary_id})
    for index, value in enumerate(extra):
        if isinstance(value, str):
            selectors.append({"version": value, "type": "", "id": ""})
        elif isinstance(value, dict) and set(value) <= {"version", "type", "id"}:
            selectors.append({"version": value.get("version", ""), "type": value.get("type", ""),
                              "id": value.get("id", "")})
        else:
            raise PublicationError(f"Invalid version selector at index {index}")
    for index, selector in enumerate(selectors):
        if not all(isinstance(selector[field], (str, int)) for field in ("version", "type", "id")):
            raise PublicationError(f"Version selector {index} has invalid fields")
        if not str(selector["version"]).strip() and not str(selector["id"]).strip():
            raise PublicationError(f"Version selector {index} needs version or id")
    return selectors


def parse_relations(env):
    try:
        relations = json.loads(env.get("CF_RELATIONS", "[]"))
    except ValueError as exc:
        raise PublicationError("CF_RELATIONS must be JSON") from exc
    if not isinstance(relations, list):
        raise PublicationError("CF_RELATIONS must be a JSON array")
    allowed = {"embeddedLibrary", "incompatible", "optionalDependency", "requiredDependency", "tool"}
    for relation in relations:
        if not isinstance(relation, dict) or set(relation) - {"slug", "projectID", "type"}:
            raise PublicationError("Invalid relation entry")
        if relation.get("type") not in allowed:
            raise PublicationError("Invalid relation type")
        if not relation.get("slug") and not relation.get("projectID"):
            raise PublicationError("Relation must identify a project")
    return relations


def run(env):
    token = required(env, "CURSEFORGE_TOKEN")
    game = required(env, "CF_GAME")
    if not re.fullmatch(r"[a-z0-9-]+", game):
        raise PublicationError("CF_GAME must be a CurseForge endpoint slug")
    project_id = positive_id(required(env, "CF_PROJECT_ID"), "CF_PROJECT_ID")
    release_type = required(env, "CF_RELEASE_TYPE")
    if release_type not in ("alpha", "beta", "release"):
        raise PublicationError("CF_RELEASE_TYPE must be alpha, beta, or release")
    changelog_type = env.get("CF_CHANGELOG_TYPE", "markdown")
    if changelog_type not in ("text", "html", "markdown"):
        raise PublicationError("CF_CHANGELOG_TYPE must be text, html, or markdown")
    dry_run = env.get("CF_DRY_RUN", "false").lower()
    manual_release = env.get("CF_MANUAL_RELEASE", "false").lower()
    if dry_run not in ("true", "false") or manual_release not in ("true", "false"):
        raise PublicationError("CF_DRY_RUN and CF_MANUAL_RELEASE must be true or false")
    artifact = Path(required(env, "CF_FILE"))
    if not artifact.is_file() or not artifact.stat().st_size:
        raise PublicationError("CF_FILE must refer to a nonempty regular file")

    parent_raw = env.get("CF_PARENT_FILE_ID", "").strip()
    parent_file_id = positive_id(parent_raw, "CF_PARENT_FILE_ID") if parent_raw else None
    selectors = parse_version_selectors(env)
    relations = parse_relations(env)
    if parent_file_id and selectors:
        raise PublicationError("CurseForge does not support gameVersions with parentFileID")
    if not parent_file_id and not selectors:
        raise PublicationError("At least one game version is required for a standalone file")
    base = f"https://{game}.curseforge.com"
    ids = []
    for selector in selectors:
        value = str(selector["id"]).strip()
        if value:
            version_id = positive_id(value, "game version ID")
        else:
            version_id = resolve_version(base, token, str(selector["version"]).strip(),
                                         str(selector["type"]).strip())
        if version_id not in ids:
            ids.append(version_id)
    file_id = None
    if dry_run != "true":
        metadata = {
            "releaseType": release_type,
            "changelog": env.get("CF_CHANGELOG", ""),
            "changelogType": changelog_type,
        }
        if ids:
            metadata["gameVersions"] = ids
        if parent_file_id:
            metadata["parentFileID"] = parent_file_id
        if relations:
            metadata["relations"] = {"projects": relations}
        if manual_release == "true":
            metadata["isMarkedForManualRelease"] = True
        if env.get("CF_DISPLAY_NAME", ""):
            metadata["displayName"] = env["CF_DISPLAY_NAME"]
        file_id = publish(base, token, project_id, artifact, metadata)
    output = env.get("GITHUB_OUTPUT")
    if output:
        with open(output, "a", encoding="utf-8") as file:
            file.write(f"game-version-id={ids[0] if ids else ''}\n")
            file.write(f"game-version-ids={','.join(str(v) for v in ids)}\n")
            file.write(f"file-id={file_id or ''}\n")
    print(f"CurseForge game version IDs: {ids}")
    print("Dry run: no file uploaded" if file_id is None else f"CurseForge file ID: {file_id}")
    return ids[0] if ids else None, file_id


if __name__ == "__main__":
    try:
        run(os.environ)
    except (PublicationError, OSError) as exc:
        print(f"::error::{exc}", file=sys.stderr)
        sys.exit(1)
