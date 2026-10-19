#!/usr/bin/env python3
"""Publish a prebuilt artifact through the CurseForge project upload API.

No implicit retry: an interrupted upload may already have succeeded.
"""
import http.client
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


def resolve_version(base, token, version, version_type, catalogs=None):
    if catalogs is None:
        catalogs = {}
    if "versions" not in catalogs:
        catalogs["versions"] = request_json(base + "/api/game/versions", token)
    versions = catalogs["versions"]
    if not isinstance(versions, list):
        raise PublicationError("Unexpected CurseForge versions response")
    candidates = [row for row in versions if isinstance(row, dict) and
                  (exact(version, row.get("name")) or exact(version, row.get("slug")))]
    if version_type:
        if "types" not in catalogs:
            catalogs["types"] = request_json(base + "/api/game/version-types", token)
        types = catalogs["types"]
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


def multipart_parts(metadata, artifact):
    boundary = "curseforge-" + uuid.uuid4().hex
    filename = artifact.name.replace('"', "").replace("\r", "").replace("\n", "")
    header = (
        f'--{boundary}\r\nContent-Disposition: form-data; name="metadata"\r\n\r\n'.encode()
        + json.dumps(metadata, ensure_ascii=False).encode("utf-8")
        + f'\r\n--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="{filename}"\r\n'
          'Content-Type: application/octet-stream\r\n\r\n'.encode()
    )
    footer = f'\r\n--{boundary}--\r\n'.encode()
    return header, footer, f"multipart/form-data; boundary={boundary}"


def publish(base, token, project_id, artifact, metadata):
    # Content-Length is known; no chunked transfer or full-file buffering required.
    header, footer, content_type = multipart_parts(metadata, artifact)
    endpoint = f"/api/projects/{project_id}/upload-file"
    connection = http.client.HTTPSConnection(base[len("https://"):] if base.startswith("https://") else base, timeout=120)
    try:
        connection.putrequest("POST", endpoint)
        connection.putheader("X-Api-Token", token)
        connection.putheader("Accept", "application/json")
        connection.putheader("Content-Type", content_type)
        connection.putheader("Content-Length", str(len(header) + artifact.stat().st_size + len(footer)))
        connection.endheaders()
        connection.send(header)
        with artifact.open("rb") as stream:
            while True:
                chunk = stream.read(1024 * 1024)
                if not chunk:
                    break
                connection.send(chunk)
        connection.send(footer)
        response = connection.getresponse()
        if not 200 <= response.status < 300:
            if 400 <= response.status < 500 and response.status not in (408,):
                raise PublicationError(
                    f"CurseForge upload rejected (HTTP {response.status}); correct the request before retrying")
            raise PublicationError(
                f"CurseForge upload HTTP {response.status}; verify published files before retrying")
        try:
            result = json.load(response)
        except (ValueError, UnicodeError) as error:
            raise PublicationError("Invalid upload response; verify files before retrying") from error
    except (OSError, TimeoutError, http.client.HTTPException) as error:
        raise PublicationError("Upload outcome unknown; verify CurseForge files before retrying") from error
    finally:
        connection.close()
    if not isinstance(result, dict):
        raise PublicationError("Unexpected upload response; verify files before retrying")
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
    primary_type = env.get("CF_GAME_VERSION_TYPE", "").strip()
    if primary_id and primary_version:
        raise PublicationError("CF_GAME_VERSION_ID and CF_GAME_VERSION are mutually exclusive")
    if primary_type and not primary_version:
        raise PublicationError("CF_GAME_VERSION_TYPE requires CF_GAME_VERSION")
    if (primary_version or primary_id or primary_type) and extra:
        raise PublicationError("CF_GAME_VERSION/CF_GAME_VERSION_ID and CF_GAME_VERSIONS are mutually exclusive")
    if primary_version or primary_id:
        selectors.append({"version": primary_version, "type": primary_type,
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
        if str(selector["id"]).strip() and (str(selector["version"]).strip() or str(selector["type"]).strip()):
            raise PublicationError(f"Version selector {index} cannot mix id with version or type")
        if not str(selector["version"]).strip() and not str(selector["id"]).strip():
            raise PublicationError(f"Version selector {index} needs version or id")
    return selectors


def parse_version_names(env):
    try:
        names = json.loads(env.get("CF_GAME_VERSION_NAMES", "[]"))
    except ValueError as error:
        raise PublicationError("CF_GAME_VERSION_NAMES must be a JSON array") from error
    if not isinstance(names, list) or any(not isinstance(n, str) or not n.strip() for n in names):
        raise PublicationError("CF_GAME_VERSION_NAMES must contain nonempty strings")
    return list(dict.fromkeys(names))


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
        slug = relation.get("slug")
        project_id = relation.get("projectID")
        if slug is not None and (not isinstance(slug, str) or not slug.strip()):
            raise PublicationError("Relation slug must be a nonempty string")
        if project_id is not None:
            if isinstance(project_id, bool) or not re.fullmatch(r"[0-9]+", str(project_id)) or int(project_id) <= 0:
                raise PublicationError("Relation projectID must be a positive integer")
            relation["projectID"] = str(project_id)
        if slug is None and project_id is None:
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
    names = parse_version_names(env)
    if names and selectors:
        raise PublicationError("CF_GAME_VERSION_NAMES and ID-resolving selectors are mutually exclusive")
    if names and env.get("CF_GAME_VERSION_TYPE", "").strip():
        raise PublicationError("CF_GAME_VERSION_TYPE cannot disambiguate native names")
    relations = parse_relations(env)
    if parent_file_id and (selectors or names):
        raise PublicationError("CurseForge does not support gameVersions with parentFileID")
    if not parent_file_id and not (selectors or names):
        raise PublicationError("At least one game version is required for a standalone file")
    base = f"https://{game}.curseforge.com"
    ids = []
    catalogs = {}
    version_outputs = []
    for selector in selectors:
        value = str(selector["id"]).strip()
        if value:
            version_id = positive_id(value, "game version ID")
        else:
            version_id = resolve_version(base, token, str(selector["version"]).strip(),
                                         str(selector["type"]).strip(), catalogs)
        if version_id not in ids:
            ids.append(version_id)
        output_entry = {}
        if str(selector["version"]).strip():
            output_entry["version"] = str(selector["version"]).strip()
        if str(selector["type"]).strip():
            output_entry["type"] = str(selector["type"]).strip()
        output_entry["versionId"] = version_id
        version_outputs.append(output_entry)
    version_outputs.extend({"version": name} for name in names)
    file_id = None
    if dry_run != "true":
        metadata = {
            "releaseType": release_type,
            "changelog": env.get("CF_CHANGELOG", ""),
            "changelogType": changelog_type,
        }
        if ids:
            metadata["gameVersions"] = ids
        if names:
            metadata["gameVersionNames"] = names
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
            file.write(f"game-versions={json.dumps(version_outputs, separators=(',', ':'))}\n")
            file.write(f"file-id={file_id or ''}\n")
    print(f"CurseForge game version IDs: {ids}")
    print("Dry run: no file uploaded" if file_id is None else f"CurseForge file ID: {file_id}")
    return ids[0] if ids else None, file_id


def error_message(error):
    # Never emit untrusted exception text as a GitHub workflow command.
    return "CurseForge publish error: " + str(error).replace("\r", "\\r").replace("\n", "\\n")


if __name__ == "__main__":
    try:
        run(os.environ)
    except (PublicationError, OSError) as exc:
        print(error_message(exc), file=sys.stderr)
        sys.exit(1)
