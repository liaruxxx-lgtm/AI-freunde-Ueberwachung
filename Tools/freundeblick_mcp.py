#!/usr/bin/env python3
"""MCP server for a local FreundeBlick JSON library.

The implementation intentionally uses only Python's standard library.  The
stdio transport is newline-delimited JSON-RPC 2.0; stdout is reserved
exclusively for protocol messages.
"""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import ipaddress
import json
import os
import re
import sys
import tempfile
import unicodedata
import uuid
from collections import Counter
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence
from urllib.parse import urlsplit


PROTOCOL_VERSION = "2025-11-25"
SUPPORTED_PROTOCOL_VERSIONS = (
    PROTOCOL_VERSION,
    "2025-06-18",
    "2025-03-26",
    "2024-11-05",
)
SERVER_NAME = "freundeblick"
SERVER_VERSION = "0.2.0"


class FriendLibraryError(Exception):
    """Base class for errors that can be corrected by the tool caller."""


class FriendLibraryInputError(FriendLibraryError):
    """Raised for invalid or ambiguous tool input."""


class FriendLibraryNotFoundError(FriendLibraryError):
    """Raised when a requested person or data file cannot be found."""


def _normalized(value: Any) -> str:
    text = unicodedata.normalize("NFKD", str(value or "")).casefold()
    text = "".join(character for character in text if not unicodedata.combining(character))
    return " ".join(re.findall(r"[a-z0-9]+", text))


def _string(value: Any, default: str = "") -> str:
    if value is None:
        return default
    return str(value)


def _string_list(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, str):
        return [value] if value else []
    if isinstance(value, Sequence) and not isinstance(value, (bytes, bytearray)):
        return [str(item) for item in value if item is not None and str(item)]
    return [str(value)]


def _number(value: Any) -> float | int | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return value
    try:
        parsed = float(str(value))
    except (TypeError, ValueError):
        return None
    return int(parsed) if parsed.is_integer() else parsed


def _boolean(value: Any, default: bool = False) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)) and value in (0, 1):
        return bool(value)
    normalized = _normalized(value)
    if normalized in {"1", "true", "yes", "ja", "confirmed", "bestatigt"}:
        return True
    if normalized in {"0", "false", "no", "nein", "unconfirmed", "unbestatigt"}:
        return False
    return default


def _first(mapping: Mapping[str, Any], *keys: str, default: Any = None) -> Any:
    for key in keys:
        if key in mapping and mapping[key] is not None:
            return mapping[key]
    return default


def _stable_fallback_id(prefix: str, value: Mapping[str, Any]) -> str:
    serialized = json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), default=str
    )
    digest = hashlib.sha256(serialized.encode("utf-8")).hexdigest()[:12]
    return f"{prefix}-{digest}"


def _deduplicated_paths(paths: Iterable[Path]) -> list[Path]:
    result: list[Path] = []
    seen: set[str] = set()
    for candidate in paths:
        expanded = candidate.expanduser()
        marker = str(expanded)
        if marker not in seen:
            result.append(expanded)
            seen.add(marker)
    return result


def data_path_candidates(explicit_path: str | os.PathLike[str] | None = None) -> list[Path]:
    """Return deterministic read-only lookup locations for ``friends.json``."""

    if explicit_path is not None:
        return [Path(explicit_path)]

    candidates: list[Path] = []
    data_file = os.environ.get("FREUNDEBLICK_DATA_FILE")
    if data_file:
        candidates.append(Path(data_file))

    data_directory = os.environ.get("FREUNDEBLICK_DATA_DIR")
    if data_directory:
        candidates.append(Path(data_directory) / "friends.json")

    candidates.extend(
        (
            Path.cwd() / "FreundeblickData" / "friends.json",
            Path(__file__).resolve().parents[1] / "FreundeblickData" / "friends.json",
            Path.home()
            / "Library"
            / "Application Support"
            / "Freundeblick"
            / "FreundeblickData"
            / "friends.json",
            Path.home()
            / "Library"
            / "Application Support"
            / "Freundeblick"
            / "friends.json",
        )
    )
    return _deduplicated_paths(candidates)


def resolve_data_path(explicit_path: str | os.PathLike[str] | None = None) -> Path:
    """Resolve the first existing FreundeBlick data file without creating it."""

    candidates = data_path_candidates(explicit_path)
    for candidate in candidates:
        if candidate.is_file():
            return candidate.resolve()
    attempted = ", ".join(str(path) for path in candidates)
    raise FriendLibraryNotFoundError(
        f"FreundeBlick-Datenbank nicht gefunden. Geprüfte Pfade: {attempted}"
    )


class FriendLibrary:
    """Normalized read/write view over ``FreundeblickData/friends.json``."""

    _CONFIRMED_STATUSES = {
        "",
        "accepted",
        "active",
        "bestatigt",
        "bestaetigt",
        "confirmed",
        "verified",
    }
    _SUGGESTED_STATUSES = {
        "candidate",
        "claimed",
        "inferred",
        "likely",
        "pending",
        "proposed",
        "suggested",
        "unverified",
        "vorgeschlagen",
    }
    _REJECTED_STATUSES = {
        "denied",
        "disputed",
        "ended",
        "inactive",
        "rejected",
        "removed",
        "widerrufen",
    }
    _FRIENDSHIP_KINDS = {
        "",
        "befreundet",
        "friend",
        "friends",
        "friendship",
        "freund",
        "freundschaft",
    }
    _QUESTION_STOPWORDS = {
        "a",
        "all",
        "alles",
        "als",
        "an",
        "and",
        "auf",
        "aus",
        "beim",
        "das",
        "der",
        "die",
        "ein",
        "eine",
        "er",
        "es",
        "etwas",
        "for",
        "fur",
        "für",
        "hat",
        "have",
        "ich",
        "in",
        "ist",
        "is",
        "man",
        "mir",
        "mit",
        "of",
        "sag",
        "sage",
        "sie",
        "the",
        "uber",
        "über",
        "und",
        "von",
        "was",
        "welche",
        "welcher",
        "wer",
        "wie",
        "wo",
        "zu",
    }

    def __init__(self, data_path: Path, payload: Mapping[str, Any]):
        self.data_path = data_path.resolve()
        self.data_directory = self.data_path.parent.resolve()
        self._payload = dict(payload)

        self.people = self._canonical_collection(
            ("people", "persons", "friends"), self._canonical_person
        )
        self.relationship_claims = self._canonical_collection(
            ("relationshipClaims", "relationship_claims", "relationships", "claims"),
            self._canonical_claim,
        )
        self.groups = self._canonical_collection(
            ("groups", "friendGroups", "friend_groups"), self._canonical_group
        )
        self.media = self._canonical_collection(
            ("media", "mediaItems", "media_items", "assets"), self._canonical_media
        )
        self.observations = self._canonical_collection(
            ("observations", "personObservations", "person_observations"),
            self._canonical_observation,
        )
        self._people_by_id = {person["id"]: person for person in self.people}

    @classmethod
    def from_path(
        cls, data_path: str | os.PathLike[str] | None = None
    ) -> "FriendLibrary":
        path = resolve_data_path(data_path)
        try:
            with path.open("r", encoding="utf-8") as handle:
                payload = json.load(handle)
        except OSError as error:
            raise FriendLibraryNotFoundError(
                f"FreundeBlick-Datenbank konnte nicht gelesen werden: {error}"
            ) from error
        except json.JSONDecodeError as error:
            raise FriendLibraryInputError(
                f"FreundeBlick-Datenbank enthält ungültiges JSON "
                f"(Zeile {error.lineno}, Spalte {error.colno})."
            ) from error

        if not isinstance(payload, Mapping):
            raise FriendLibraryInputError(
                "FreundeBlick-Datenbank muss ein JSON-Objekt als Wurzel haben."
            )
        return cls(path, payload)

    @property
    def metadata(self) -> dict[str, Any]:
        return {
            "schemaVersion": _first(
                self._payload, "schemaVersion", "schema_version", default=None
            ),
            "lastUpdated": _first(
                self._payload, "lastUpdated", "last_updated", default=None
            ),
            "dataFile": str(self.data_path),
            "readOnly": False,
        }

    @staticmethod
    def _timestamp() -> str:
        return (
            datetime.now(timezone.utc)
            .isoformat(timespec="seconds")
            .replace("+00:00", "Z")
        )

    @staticmethod
    def _validated_timestamp(value: Any, field: str) -> str | None:
        if value is None:
            return None
        if not isinstance(value, str) or not value.strip():
            raise FriendLibraryInputError(
                f"{field} muss ein ISO-Datum oder null sein."
            )
        candidate = value.strip()
        if re.fullmatch(r"\d{4}-\d{2}-\d{2}", candidate):
            candidate += "T00:00:00Z"
        try:
            parsed = datetime.fromisoformat(candidate.replace("Z", "+00:00"))
        except ValueError as error:
            raise FriendLibraryInputError(
                f"{field} muss ein ISO-Datum sein (z. B. 2000-01-31)."
            ) from error
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=timezone.utc)
        return (
            parsed.astimezone(timezone.utc)
            .isoformat(timespec="seconds")
            .replace("+00:00", "Z")
        )

    @staticmethod
    def _validated_strings(value: Any, field: str) -> list[str]:
        if not isinstance(value, Sequence) or isinstance(
            value, (str, bytes, bytearray)
        ):
            raise FriendLibraryInputError(
                f"{field} muss eine Liste von Zeichenketten sein."
            )
        result: list[str] = []
        for item in value:
            if not isinstance(item, str):
                raise FriendLibraryInputError(
                    f"{field} darf nur Zeichenketten enthalten."
                )
            trimmed = item.strip()
            if trimmed and trimmed not in result:
                result.append(trimmed)
        return result

    @staticmethod
    def _standard_collection(payload: dict[str, Any], key: str) -> list[Any]:
        value = payload.get(key)
        if value is None:
            payload[key] = []
            return payload[key]
        if not isinstance(value, list):
            raise FriendLibraryInputError(
                f"Die Datenbank-Eigenschaft '{key}' muss eine Liste sein."
            )
        return value

    def _write_payload(self, mutation: Any) -> Any:
        """Apply one locked mutation and atomically replace ``friends.json``."""

        lock_path = self.data_path.with_name(self.data_path.name + ".lock")
        lock_path.parent.mkdir(parents=True, exist_ok=True)
        with lock_path.open("a+", encoding="utf-8") as lock:
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
            latest = FriendLibrary.from_path(self.data_path)
            payload = dict(latest._payload)
            result = mutation(payload, latest)
            payload["schemaVersion"] = payload.get("schemaVersion", 1)
            payload["lastUpdated"] = self._timestamp()

            temporary_fd, temporary_name = tempfile.mkstemp(
                prefix=".friends-", suffix=".tmp", dir=self.data_path.parent
            )
            try:
                with os.fdopen(temporary_fd, "w", encoding="utf-8") as handle:
                    json.dump(
                        payload,
                        handle,
                        ensure_ascii=False,
                        indent=2,
                        sort_keys=True,
                    )
                    handle.write("\n")
                    handle.flush()
                    os.fsync(handle.fileno())
                os.replace(temporary_name, self.data_path)
            except Exception:
                try:
                    os.unlink(temporary_name)
                except FileNotFoundError:
                    pass
                raise
            finally:
                fcntl.flock(lock.fileno(), fcntl.LOCK_UN)

        refreshed = FriendLibrary.from_path(self.data_path)
        self.__dict__.update(refreshed.__dict__)
        return result

    def save_person(self, values: Mapping[str, Any]) -> dict[str, Any]:
        """Create a person or partially update an explicitly selected person."""

        def mutate(
            payload: dict[str, Any], latest: "FriendLibrary"
        ) -> tuple[str, str]:
            people = self._standard_collection(payload, "people")
            identifier = values.get("person")
            existing_id: str | None = None
            if identifier is not None:
                if not isinstance(identifier, str) or not identifier.strip():
                    raise FriendLibraryInputError(
                        "person muss eine nicht leere ID, ein Name oder ein Alias sein."
                    )
                existing_id = latest.find_person(identifier)["id"]

            index: int | None = None
            if existing_id is not None:
                for candidate_index, raw in enumerate(people):
                    if isinstance(raw, Mapping) and _string(raw.get("id")) == existing_id:
                        index = candidate_index
                        break
                if index is None:
                    raise FriendLibraryNotFoundError(
                        f"Person {existing_id} wurde in der Datenbank nicht gefunden."
                    )

            creating = index is None
            if creating:
                raw_person: dict[str, Any] = {
                    "id": str(uuid.uuid4()),
                    "name": "",
                    "aliases": [],
                    "summary": "",
                    "temperamentTags": [],
                    "interests": [],
                    "links": [],
                    "createdAt": self._timestamp(),
                }
            else:
                raw_person = dict(people[index])  # type: ignore[index]

            if "name" in values:
                name = values["name"]
                if not isinstance(name, str) or not name.strip():
                    raise FriendLibraryInputError(
                        "name muss eine nicht leere Zeichenkette sein."
                    )
                raw_person["name"] = name.strip()
            elif creating:
                raise FriendLibraryInputError(
                    "Beim Anlegen einer Person ist name erforderlich."
                )

            for field in ("aliases", "temperamentTags", "interests"):
                if field in values:
                    raw_person[field] = self._validated_strings(values[field], field)
            if "profileDetails" in values:
                raw_details = values["profileDetails"]
                if not isinstance(raw_details, Mapping):
                    raise FriendLibraryInputError(
                        "profileDetails muss ein Objekt mit Listen von Zeichenketten sein."
                    )
                validated_details: dict[str, list[str]] = {}
                for raw_key, raw_values in raw_details.items():
                    if not isinstance(raw_key, str) or not raw_key.strip():
                        raise FriendLibraryInputError(
                            "Jeder Schlüssel in profileDetails muss eine "
                            "nicht leere Zeichenkette sein."
                        )
                    validated_details[raw_key.strip()] = self._validated_strings(
                        raw_values, f"profileDetails.{raw_key}"
                    )
                raw_person["profileDetails"] = validated_details
            for field in ("summary",):
                if field in values:
                    value = values[field]
                    if not isinstance(value, str):
                        raise FriendLibraryInputError(
                            f"{field} muss eine Zeichenkette sein."
                        )
                    raw_person[field] = value.strip()
            if "location" in values:
                location = values["location"]
                if location is not None and not isinstance(location, str):
                    raise FriendLibraryInputError(
                        "location muss eine Zeichenkette oder null sein."
                    )
                raw_person["location"] = location.strip() if location else None
            if "birthday" in values:
                raw_person["birthday"] = self._validated_timestamp(
                    values["birthday"], "birthday"
                )

            if creating:
                people.append(raw_person)
            else:
                people[index] = raw_person  # type: ignore[index]
            return ("created" if creating else "updated", raw_person["id"])

        action, person_id = self._write_payload(mutate)
        return {
            "action": action,
            "person": self._person_brief(self.find_person(person_id)),
            "metadata": self.metadata,
        }

    def save_profile_link(self, values: Mapping[str, Any]) -> dict[str, Any]:
        """Create or update one safe public HTTPS link on a person."""

        person = _required_string(values, "person")
        url = _required_string(values, "url").strip()
        parsed = urlsplit(url)
        try:
            literal_ip = ipaddress.ip_address(parsed.hostname or "")
        except ValueError:
            literal_ip = None
        if (
            parsed.scheme.casefold() != "https"
            or not parsed.hostname
            or parsed.username is not None
            or parsed.password is not None
            or parsed.hostname.casefold() == "localhost"
            or (literal_ip is not None and not literal_ip.is_global)
        ):
            raise FriendLibraryInputError(
                "url muss eine öffentliche HTTPS-Adresse ohne Zugangsdaten sein."
            )

        allowed_platforms = {
            "website",
            "instagram",
            "tiktok",
            "youtube",
            "linkedin",
            "x",
            "facebook",
            "snapchat",
            "threads",
            "mastodon",
            "github",
            "other",
        }
        platform = _string(values.get("platform", "website")).strip()
        if platform not in allowed_platforms:
            raise FriendLibraryInputError(
                "platform ist ungültig. Erlaubt: "
                + ", ".join(sorted(allowed_platforms))
                + "."
            )

        def mutate(
            payload: dict[str, Any], latest: "FriendLibrary"
        ) -> tuple[str, str, str]:
            selected = latest.find_person(person)
            people = self._standard_collection(payload, "people")
            for index, raw in enumerate(people):
                if not isinstance(raw, Mapping) or _string(raw.get("id")) != selected["id"]:
                    continue
                updated = dict(raw)
                links = updated.get("links", [])
                if not isinstance(links, list):
                    raise FriendLibraryInputError(
                        "Die gespeicherten Profil-Links müssen eine Liste sein."
                    )
                link_id = values.get("linkID")
                matching_indexes = [
                    link_index
                    for link_index, link in enumerate(links)
                    if isinstance(link, Mapping)
                    and (
                        (link_id is not None and _string(link.get("id")) == link_id)
                        or (link_id is None and _string(link.get("url")) == url)
                    )
                ]
                if link_id is not None and not matching_indexes:
                    raise FriendLibraryNotFoundError(
                        f"Profil-Link {link_id} wurde nicht gefunden."
                    )
                creating = not matching_indexes
                link_index = matching_indexes[0] if matching_indexes else None
                stored = (
                    dict(links[link_index])
                    if link_index is not None
                    else {
                        "id": str(uuid.uuid4()),
                        "createdAt": self._timestamp(),
                    }
                )
                stored.update(
                    {
                        "kind": "website" if platform == "website" else "socialMedia",
                        "platform": platform,
                        "title": _string(values.get("title")).strip(),
                        "url": url,
                        "handle": _string(values.get("handle")).strip(),
                        "confirmed": values.get("confirmed", False),
                    }
                )
                if creating:
                    links.append(stored)
                else:
                    links[link_index] = stored  # type: ignore[index]
                updated["links"] = links
                people[index] = updated
                return (
                    "created" if creating else "updated",
                    selected["id"],
                    stored["id"],
                )
            raise FriendLibraryNotFoundError(
                f"Person {selected['id']} wurde in der Datenbank nicht gefunden."
            )

        action, person_id, link_id = self._write_payload(mutate)
        updated_person = self.find_person(person_id)
        link = next(item for item in updated_person["links"] if item["id"] == link_id)
        return {
            "action": action,
            "person": self._person_brief(updated_person),
            "link": dict(link),
            "metadata": self.metadata,
        }

    def save_relationship(self, values: Mapping[str, Any]) -> dict[str, Any]:
        """Upsert one directed relationship, optionally in both directions."""

        allowed_kinds = {
            "friendship",
            "family",
            "romantic",
            "school",
            "work",
            "acquaintance",
            "other",
        }
        allowed_statuses = {"claimed", "confirmed", "disputed", "rejected", "ended"}
        allowed_sources = {
            "manual",
            "personStatement",
            "mediaAnalysis",
            "inferred",
            "imported",
        }
        allowed_family_roles = {
            "familyMember",
            "parent",
            "child",
            "sibling",
            "grandparent",
            "grandchild",
            "auntUncle",
            "nieceNephew",
            "cousin",
            "spouse",
            "stepfamily",
            "inLaw",
        }
        inverse_family_roles = {
            "parent": "child",
            "child": "parent",
            "grandparent": "grandchild",
            "grandchild": "grandparent",
            "auntUncle": "nieceNephew",
            "nieceNephew": "auntUncle",
        }
        kind = _string(values.get("kind", "friendship"))
        family_role = _string(values.get("familyRole", "familyMember"))
        status = _string(values.get("status", "claimed"))
        source = _string(values.get("source", "manual"))
        if kind not in allowed_kinds:
            raise FriendLibraryInputError("kind ist ungültig.")
        if status not in allowed_statuses:
            raise FriendLibraryInputError("status ist ungültig.")
        if source not in allowed_sources:
            raise FriendLibraryInputError("source ist ungültig.")
        if kind == "family" and family_role not in allowed_family_roles:
            raise FriendLibraryInputError("familyRole ist ungültig.")
        if kind != "family" and values.get("familyRole") is not None:
            raise FriendLibraryInputError(
                "familyRole darf nur bei kind=family verwendet werden."
            )
        notes = _string(values.get("notes")).strip()
        reciprocal = values.get("reciprocal", False)

        def mutate(
            payload: dict[str, Any], latest: "FriendLibrary"
        ) -> list[tuple[str, str]]:
            first = latest.find_person(_required_string(values, "fromPerson"))
            second = latest.find_person(_required_string(values, "toPerson"))
            if first["id"] == second["id"]:
                raise FriendLibraryInputError(
                    "Eine Person kann keine Beziehung zu sich selbst eintragen."
                )
            pairs = [(first["id"], second["id"])]
            if reciprocal:
                pairs.append((second["id"], first["id"]))
            claims = self._standard_collection(payload, "relationshipClaims")
            results: list[tuple[str, str]] = []
            for pair_index, (from_id, to_id) in enumerate(pairs):
                matches = [
                    index
                    for index, claim in enumerate(claims)
                    if isinstance(claim, Mapping)
                    and _string(claim.get("fromPersonID")) == from_id
                    and _string(claim.get("toPersonID")) == to_id
                    and _string(claim.get("kind", "friendship")) == kind
                ]
                if len(matches) > 1:
                    raise FriendLibraryInputError(
                        "Mehrere passende Beziehungsangaben existieren; bitte zuerst "
                        "in der App bereinigen."
                    )
                creating = not matches
                claim_index = matches[0] if matches else None
                claim = (
                    dict(claims[claim_index])
                    if claim_index is not None
                    else {"id": str(uuid.uuid4()), "createdAt": self._timestamp()}
                )
                claim.update(
                    {
                        "fromPersonID": from_id,
                        "toPersonID": to_id,
                        "kind": kind,
                        "status": status,
                        "source": source,
                        "notes": notes,
                    }
                )
                if kind == "family":
                    claim["familyRole"] = (
                        inverse_family_roles.get(family_role, family_role)
                        if pair_index == 1
                        else family_role
                    )
                else:
                    claim.pop("familyRole", None)
                if creating:
                    claims.append(claim)
                else:
                    claims[claim_index] = claim  # type: ignore[index]
                results.append(("created" if creating else "updated", claim["id"]))
            return results

        results = self._write_payload(mutate)
        saved = [
            next(
                dict(claim)
                for claim in self.relationship_claims
                if claim["id"] == claim_id
            )
            | {"action": action}
            for action, claim_id in results
        ]
        return {"relationships": saved, "metadata": self.metadata}

    def save_observation(self, values: Mapping[str, Any]) -> dict[str, Any]:
        """Create or update a sourced observation."""

        allowed_categories = {
            "identity",
            "location",
            "personality",
            "clothing",
            "appearance",
            "interest",
            "preference",
            "habit",
            "biography",
            "other",
        }
        allowed_statuses = {
            "unverified",
            "likely",
            "confirmed",
            "disputed",
            "archived",
        }
        allowed_sources = {
            "manual",
            "personStatement",
            "mediaAnalysis",
            "inferred",
            "imported",
        }
        category = _required_string(values, "category")
        value = _required_string(values, "value").strip()
        status = _string(values.get("status", "unverified"))
        source = _string(values.get("source", "manual"))
        confidence = values.get("confidence", 0.5)
        if category not in allowed_categories:
            raise FriendLibraryInputError("category ist ungültig.")
        if status not in allowed_statuses:
            raise FriendLibraryInputError("status ist ungültig.")
        if source not in allowed_sources:
            raise FriendLibraryInputError("source ist ungültig.")
        if isinstance(confidence, bool) or not isinstance(confidence, (int, float)):
            raise FriendLibraryInputError("confidence muss eine Zahl sein.")
        if not 0 <= confidence <= 1:
            raise FriendLibraryInputError("confidence muss zwischen 0 und 1 liegen.")
        evidence_ids = self._validated_strings(
            values.get("evidenceMediaIDs", []), "evidenceMediaIDs"
        )

        def mutate(
            payload: dict[str, Any], latest: "FriendLibrary"
        ) -> tuple[str, str]:
            selected = latest.find_person(_required_string(values, "person"))
            missing_media = sorted(
                set(evidence_ids) - {item["id"] for item in latest.media}
            )
            if missing_media:
                raise FriendLibraryNotFoundError(
                    "Unbekannte evidenceMediaIDs: " + ", ".join(missing_media) + "."
                )
            observations = self._standard_collection(payload, "observations")
            observation_id = values.get("observationID")
            matches = [
                index
                for index, observation in enumerate(observations)
                if isinstance(observation, Mapping)
                and observation_id is not None
                and _string(observation.get("id")) == observation_id
            ]
            if observation_id is not None and not matches:
                raise FriendLibraryNotFoundError(
                    f"Beobachtung {observation_id} wurde nicht gefunden."
                )
            creating = not matches
            observation_index = matches[0] if matches else None
            observation = (
                dict(observations[observation_index])
                if observation_index is not None
                else {"id": str(uuid.uuid4()), "createdAt": self._timestamp()}
            )
            observation.update(
                {
                    "personID": selected["id"],
                    "category": category,
                    "value": value,
                    "status": status,
                    "confidence": float(confidence),
                    "source": source,
                    "evidenceMediaIDs": evidence_ids,
                }
            )
            if creating:
                observations.append(observation)
            else:
                observations[observation_index] = observation  # type: ignore[index]
            return ("created" if creating else "updated", observation["id"])

        action, observation_id = self._write_payload(mutate)
        observation = next(
            dict(item) for item in self.observations if item["id"] == observation_id
        )
        return {
            "action": action,
            "observation": observation,
            "metadata": self.metadata,
        }

    def _raw_collection(self, keys: Sequence[str]) -> list[Mapping[str, Any]]:
        raw: Any = None
        for key in keys:
            if key in self._payload:
                raw = self._payload[key]
                break
        if raw is None:
            return []
        if isinstance(raw, Mapping):
            result: list[Mapping[str, Any]] = []
            for item_id, item in raw.items():
                if isinstance(item, Mapping):
                    copied = dict(item)
                    copied.setdefault("id", str(item_id))
                    result.append(copied)
            return result
        if isinstance(raw, Sequence) and not isinstance(raw, (str, bytes, bytearray)):
            return [item for item in raw if isinstance(item, Mapping)]
        return []

    def _canonical_collection(
        self, keys: Sequence[str], canonicalizer: Any
    ) -> list[dict[str, Any]]:
        items = [canonicalizer(item) for item in self._raw_collection(keys)]
        return sorted(items, key=lambda item: (_normalized(item.get("name")), item["id"]))

    @staticmethod
    def _canonical_person(raw: Mapping[str, Any]) -> dict[str, Any]:
        person_id = _string(_first(raw, "id", "personID", "person_id"))
        if not person_id:
            person_id = _stable_fallback_id("person", raw)
        name = _string(_first(raw, "name", "displayName", "display_name"))
        raw_links = _first(
            raw,
            "links",
            "publicLinks",
            "public_links",
            "socialLinks",
            "social_links",
            default=[],
        )
        links: list[dict[str, Any]] = []
        if isinstance(raw_links, Sequence) and not isinstance(
            raw_links, (str, bytes, bytearray)
        ):
            for raw_link in raw_links:
                if not isinstance(raw_link, Mapping):
                    continue
                link_id = _string(_first(raw_link, "id", "linkID", "link_id"))
                if not link_id:
                    link_id = _stable_fallback_id("link", raw_link)
                links.append(
                    {
                        "id": link_id,
                        "kind": _string(
                            _first(raw_link, "kind", "type", default="website")
                        ),
                        "platform": _string(
                            _first(raw_link, "platform", "service", "provider")
                        ),
                        "title": _string(
                            _first(raw_link, "title", "name", "label")
                        ),
                        "url": _string(_first(raw_link, "url", "href", "link")),
                        "handle": _string(
                            _first(raw_link, "handle", "username", "account")
                        ),
                        "confirmed": _boolean(
                            _first(
                                raw_link,
                                "confirmed",
                                "isConfirmed",
                                "is_confirmed",
                                default=False,
                            )
                        ),
                        "createdAt": _first(raw_link, "createdAt", "created_at"),
                    }
                )
        raw_profile_details = _first(
            raw, "profileDetails", "profile_details", default={}
        )
        profile_details: dict[str, list[str]] = {}
        if isinstance(raw_profile_details, Mapping):
            for detail_key, detail_values in raw_profile_details.items():
                key = _string(detail_key).strip()
                if key:
                    profile_details[key] = _string_list(detail_values)
        return {
            "id": person_id,
            "name": name,
            "aliases": _string_list(_first(raw, "aliases", "nicknames", default=[])),
            "birthday": _first(raw, "birthday", "birthDate", "birth_date"),
            "location": _first(raw, "location", "residence", "city"),
            "summary": _string(_first(raw, "summary", "bio", "notes")),
            "temperamentTags": _string_list(
                _first(
                    raw,
                    "temperamentTags",
                    "temperament_tags",
                    "personalityTags",
                    default=[],
                )
            ),
            "interests": _string_list(
                _first(raw, "interests", "hobbies", default=[])
            ),
            "profileDetails": profile_details,
            "avatarMediaID": _first(
                raw, "avatarMediaID", "avatarMediaId", "avatar_media_id"
            ),
            "links": links,
            "createdAt": _first(raw, "createdAt", "created_at"),
        }

    @staticmethod
    def _canonical_claim(raw: Mapping[str, Any]) -> dict[str, Any]:
        claim_id = _string(_first(raw, "id", "claimID", "claim_id"))
        if not claim_id:
            claim_id = _stable_fallback_id("claim", raw)
        return {
            "id": claim_id,
            "fromPersonID": _string(
                _first(
                    raw,
                    "fromPersonID",
                    "fromPersonId",
                    "from_person_id",
                    "sourcePersonID",
                    "source_id",
                )
            ),
            "toPersonID": _string(
                _first(
                    raw,
                    "toPersonID",
                    "toPersonId",
                    "to_person_id",
                    "targetPersonID",
                    "target_id",
                )
            ),
            "kind": _string(_first(raw, "kind", "type", default="friendship")),
            "familyRole": _first(raw, "familyRole", "family_role"),
            "status": _string(_first(raw, "status", default="confirmed")),
            "source": _string(_first(raw, "source")),
            "notes": _string(_first(raw, "notes", "note")),
            "createdAt": _first(raw, "createdAt", "created_at"),
        }

    @staticmethod
    def _canonical_group(raw: Mapping[str, Any]) -> dict[str, Any]:
        group_id = _string(_first(raw, "id", "groupID", "group_id"))
        if not group_id:
            group_id = _stable_fallback_id("group", raw)
        return {
            "id": group_id,
            "name": _string(_first(raw, "name", "title", default="Freundesgruppe")),
            "memberIDs": _string_list(
                _first(raw, "memberIDs", "memberIds", "member_ids", "members", default=[])
            ),
            "status": _string(_first(raw, "status", default="confirmed")),
            "confidence": _number(_first(raw, "confidence")),
            "explanation": _string(_first(raw, "explanation", "reason")),
            "createdAt": _first(raw, "createdAt", "created_at"),
            "source": "persisted",
        }

    def _safe_media_path(self, stored_filename: str) -> tuple[str | None, bool]:
        if not stored_filename:
            return None, False
        raw_path = Path(stored_filename)
        if raw_path.is_absolute():
            candidates = [raw_path]
        else:
            candidates = [
                self.data_directory / "Media" / raw_path,
                self.data_directory / raw_path,
            ]

        safe_candidates: list[Path] = []
        for candidate in candidates:
            resolved = candidate.resolve(strict=False)
            try:
                resolved.relative_to(self.data_directory)
            except ValueError:
                continue
            safe_candidates.append(resolved)

        for candidate in safe_candidates:
            if candidate.is_file():
                return str(candidate), True
        if safe_candidates:
            return str(safe_candidates[0]), False
        return None, False

    def _canonical_media(self, raw: Mapping[str, Any]) -> dict[str, Any]:
        media_id = _string(_first(raw, "id", "mediaID", "media_id"))
        if not media_id:
            media_id = _stable_fallback_id("media", raw)
        stored_filename = _string(
            _first(raw, "storedFilename", "stored_filename", "path", "filename")
        )
        local_path, available = self._safe_media_path(stored_filename)
        return {
            "id": media_id,
            "storedFilename": stored_filename,
            "originalFilename": _string(
                _first(raw, "originalFilename", "original_filename", "displayName")
            ),
            "kind": _string(_first(raw, "kind", "type")).casefold(),
            "personIDs": _string_list(
                _first(raw, "personIDs", "personIds", "person_ids", "people", default=[])
            ),
            "importedAt": _first(raw, "importedAt", "imported_at"),
            "capturedAt": _first(raw, "capturedAt", "captured_at"),
            "tags": _string_list(_first(raw, "tags", default=[])),
            "clothingTags": _string_list(
                _first(raw, "clothingTags", "clothing_tags", default=[])
            ),
            "notes": _string(_first(raw, "notes", "note")),
            "analysisLabels": _string_list(
                _first(raw, "analysisLabels", "analysis_labels", "labels", default=[])
            ),
            "localPath": local_path,
            "available": available,
        }

    @staticmethod
    def _canonical_observation(raw: Mapping[str, Any]) -> dict[str, Any]:
        observation_id = _string(
            _first(raw, "id", "observationID", "observation_id")
        )
        if not observation_id:
            observation_id = _stable_fallback_id("observation", raw)
        return {
            "id": observation_id,
            "personID": _string(
                _first(raw, "personID", "personId", "person_id", "subjectID")
            ),
            "category": _string(_first(raw, "category", "kind", "type")),
            "value": _first(raw, "value", "text", "label"),
            "status": _string(_first(raw, "status", default="suggested")),
            "confidence": _number(_first(raw, "confidence")),
            "source": _string(_first(raw, "source")),
            "evidenceMediaIDs": _string_list(
                _first(
                    raw,
                    "evidenceMediaIDs",
                    "evidenceMediaIds",
                    "evidence_media_ids",
                    default=[],
                )
            ),
            "createdAt": _first(raw, "createdAt", "created_at"),
        }

    def _person_brief(self, person: Mapping[str, Any]) -> dict[str, Any]:
        return {
            "id": person["id"],
            "name": person["name"],
            "aliases": list(person["aliases"]),
            "location": person["location"],
            "summary": person["summary"],
            "temperamentTags": list(person["temperamentTags"]),
            "interests": list(person["interests"]),
            "profileDetails": {
                key: list(values)
                for key, values in person["profileDetails"].items()
            },
            "avatarMediaID": person["avatarMediaID"],
            "links": [dict(link) for link in person["links"]],
        }

    def find_person(self, identifier: str) -> dict[str, Any]:
        identifier = _string(identifier).strip()
        if not identifier:
            raise FriendLibraryInputError("Eine Personen-ID oder ein Name ist erforderlich.")

        if identifier in self._people_by_id:
            return self._people_by_id[identifier]

        needle = _normalized(identifier)
        exact = [
            person
            for person in self.people
            if needle == _normalized(person["name"])
            or needle in {_normalized(alias) for alias in person["aliases"]}
        ]
        if len(exact) == 1:
            return exact[0]
        if len(exact) > 1:
            names = ", ".join(person["name"] for person in exact)
            raise FriendLibraryInputError(
                f"'{identifier}' ist mehrdeutig. Treffer: {names}. Bitte die ID verwenden."
            )

        partial = [
            person
            for person in self.people
            if needle in _normalized(person["name"])
            or any(needle in _normalized(alias) for alias in person["aliases"])
        ]
        if len(partial) == 1:
            return partial[0]
        if len(partial) > 1:
            names = ", ".join(person["name"] for person in partial)
            raise FriendLibraryInputError(
                f"'{identifier}' passt zu mehreren Personen: {names}. Bitte genauer fragen."
            )
        raise FriendLibraryNotFoundError(f"Keine Person für '{identifier}' gefunden.")

    def search_people(self, query: str, limit: int = 20) -> dict[str, Any]:
        limit = self._validated_limit(limit)
        query_text = _normalized(query)
        query_tokens = [
            token
            for token in query_text.split()
            if token not in self._QUESTION_STOPWORDS and len(token) > 1
        ]
        ranked: list[tuple[tuple[int, int, str, str], dict[str, Any]]] = []

        for person in self.people:
            name = _normalized(person["name"])
            aliases = [_normalized(alias) for alias in person["aliases"]]
            fields = [
                name,
                *aliases,
                _normalized(person["location"]),
                _normalized(person["summary"]),
                *(_normalized(value) for value in person["temperamentTags"]),
                *(_normalized(value) for value in person["interests"]),
                *(
                    _normalized(value)
                    for detail_key, detail_values in person["profileDetails"].items()
                    for value in (detail_key, *detail_values)
                ),
                *(
                    _normalized(value)
                    for link in person["links"]
                    for value in (
                        link["kind"],
                        link["platform"],
                        link["title"],
                        link["url"],
                        link["handle"],
                    )
                ),
            ]
            haystack = " ".join(fields)
            if not query_text:
                category, matches = 10, 0
            elif query_text == _normalized(person["id"]):
                category, matches = 0, len(query_tokens)
            elif query_text == name or query_text in aliases:
                category, matches = 1, len(query_tokens)
            elif name.startswith(query_text) or any(
                alias.startswith(query_text) for alias in aliases
            ):
                category, matches = 2, len(query_tokens)
            elif query_text in name or any(query_text in alias for alias in aliases):
                category, matches = 3, len(query_tokens)
            else:
                matches = sum(token in haystack for token in query_tokens)
                if not query_tokens or matches == 0:
                    continue
                category = 4
            rank = (category, -matches, name, person["id"])
            ranked.append((rank, self._person_brief(person)))

        ranked.sort(key=lambda item: item[0])
        people = [item[1] for item in ranked[:limit]]
        return {
            "query": query,
            "count": len(people),
            "people": people,
            "metadata": self.metadata,
        }

    @staticmethod
    def _validated_limit(limit: Any, maximum: int = 100) -> int:
        if isinstance(limit, bool) or not isinstance(limit, int):
            raise FriendLibraryInputError("limit muss eine ganze Zahl sein.")
        if limit < 1 or limit > maximum:
            raise FriendLibraryInputError(f"limit muss zwischen 1 und {maximum} liegen.")
        return limit

    @staticmethod
    def _parse_as_of(value: str | None) -> date:
        if value is None:
            return date.today()
        try:
            return date.fromisoformat(value[:10])
        except (TypeError, ValueError) as error:
            raise FriendLibraryInputError(
                "asOf muss ein ISO-Datum im Format JJJJ-MM-TT sein."
            ) from error

    def _age(self, person: Mapping[str, Any], as_of: str | None = None) -> dict[str, Any] | None:
        birthday_value = person.get("birthday")
        if not birthday_value:
            return None
        try:
            if isinstance(birthday_value, (int, float)):
                birthday = datetime.fromtimestamp(float(birthday_value)).date()
            else:
                birthday = date.fromisoformat(str(birthday_value)[:10])
        except (OSError, OverflowError, TypeError, ValueError):
            return {
                "years": None,
                "asOf": self._parse_as_of(as_of).isoformat(),
                "birthday": birthday_value,
                "source": "birthday",
                "error": "Geburtstag konnte nicht als ISO-Datum gelesen werden.",
            }
        reference = self._parse_as_of(as_of)
        years = reference.year - birthday.year - (
            (reference.month, reference.day) < (birthday.month, birthday.day)
        )
        return {
            "years": years,
            "asOf": reference.isoformat(),
            "birthday": birthday_value,
            "source": "birthday",
        }

    def _status_class(self, status: Any) -> str:
        normalized = _normalized(status)
        if normalized in self._CONFIRMED_STATUSES:
            return "confirmed"
        if normalized in self._SUGGESTED_STATUSES:
            return "suggested"
        return "other"

    def _is_confirmed_claim(self, claim: Mapping[str, Any]) -> bool:
        status = _normalized(claim.get("status"))
        return status in self._CONFIRMED_STATUSES

    def _supports_relationship_inference(self, claim: Mapping[str, Any]) -> bool:
        """Match Swift's RelationshipStatus.supportsInference semantics."""

        status = _normalized(claim.get("status"))
        return status in self._CONFIRMED_STATUSES or status == "claimed"

    def _is_friendship_claim(self, claim: Mapping[str, Any]) -> bool:
        return _normalized(claim.get("kind")) in self._FRIENDSHIP_KINDS

    def _decorate_claim(
        self, claim: Mapping[str, Any], focus_person_id: str | None = None
    ) -> dict[str, Any]:
        result = dict(claim)
        source = self._people_by_id.get(claim["fromPersonID"])
        target = self._people_by_id.get(claim["toPersonID"])
        result["fromPerson"] = self._person_brief(source) if source else None
        result["toPerson"] = self._person_brief(target) if target else None
        result["statusClass"] = self._status_class(claim.get("status"))
        if focus_person_id:
            if claim["fromPersonID"] == focus_person_id:
                result["direction"] = "outgoing"
                result["otherPerson"] = self._person_brief(target) if target else None
            else:
                result["direction"] = "incoming"
                result["otherPerson"] = self._person_brief(source) if source else None
        return result

    def _mutual_relationships(self, kind: str) -> list[dict[str, Any]]:
        directed: dict[tuple[str, str], list[str]] = {}
        for claim in self.relationship_claims:
            if (
                self._supports_relationship_inference(claim)
                and _normalized(claim.get("kind")) == _normalized(kind)
                and claim["fromPersonID"]
                and claim["toPersonID"]
                and claim["fromPersonID"] != claim["toPersonID"]
            ):
                directed.setdefault(
                    (claim["fromPersonID"], claim["toPersonID"]), []
                ).append(claim["id"])

        results: list[dict[str, Any]] = []
        processed: set[tuple[str, str]] = set()
        for source_id, target_id in sorted(directed):
            pair = tuple(sorted((source_id, target_id)))
            if pair in processed or (target_id, source_id) not in directed:
                continue
            processed.add(pair)
            people = [
                self._person_brief(self._people_by_id[person_id])
                for person_id in pair
                if person_id in self._people_by_id
            ]
            results.append(
                {
                    "personIDs": list(pair),
                    "people": people,
                    "claimIDs": sorted(
                        directed[(source_id, target_id)]
                        + directed[(target_id, source_id)]
                    ),
                    "kind": kind,
                    "status": "confirmedByBoth",
                    "derived": True,
                }
            )
        return results

    def _mutual_friendships(self) -> list[dict[str, Any]]:
        return self._mutual_relationships("friendship")

    def _mutual_families(self) -> list[dict[str, Any]]:
        return self._mutual_relationships("family")

    def get_relationships(
        self, person: str | None = None, include_unconfirmed: bool = True
    ) -> dict[str, Any]:
        focus = self.find_person(person) if person else None
        focus_id = focus["id"] if focus else None
        claims = [
            claim
            for claim in self.relationship_claims
            if (
                focus_id is None
                or focus_id in (claim["fromPersonID"], claim["toPersonID"])
            )
            and (include_unconfirmed or self._is_confirmed_claim(claim))
        ]
        decorated = [
            self._decorate_claim(claim, focus_person_id=focus_id) for claim in claims
        ]
        decorated.sort(
            key=lambda claim: (
                _normalized(
                    (claim.get("otherPerson") or {}).get("name")
                    or (claim.get("toPerson") or {}).get("name")
                ),
                claim["id"],
            )
        )
        mutual = [
            friendship
            for friendship in self._mutual_friendships()
            if focus_id is None or focus_id in friendship["personIDs"]
        ]
        mutual_families = [
            family
            for family in self._mutual_families()
            if focus_id is None or focus_id in family["personIDs"]
        ]
        return {
            "person": self._person_brief(focus) if focus else None,
            "claims": decorated,
            "mutualFriendships": mutual,
            "mutualFamilies": mutual_families,
            "counts": {
                "claims": len(decorated),
                "mutualFriendships": len(mutual),
                "mutualFamilies": len(mutual_families),
            },
            "metadata": self.metadata,
        }

    @staticmethod
    def _maximal_cliques(
        adjacency: Mapping[str, set[str]], minimum_size: int
    ) -> list[tuple[str, ...]]:
        cliques: list[tuple[str, ...]] = []

        def visit(current: set[str], possible: set[str], excluded: set[str]) -> None:
            if not possible and not excluded:
                if len(current) >= minimum_size:
                    cliques.append(tuple(sorted(current)))
                return
            pivot_candidates = possible | excluded
            pivot = (
                max(
                    sorted(pivot_candidates),
                    key=lambda node: len(possible & adjacency.get(node, set())),
                )
                if pivot_candidates
                else None
            )
            candidates = possible - (adjacency.get(pivot, set()) if pivot else set())
            for node in sorted(candidates):
                neighbours = adjacency.get(node, set())
                visit(
                    current | {node},
                    possible & neighbours,
                    excluded & neighbours,
                )
                possible.remove(node)
                excluded.add(node)

        visit(set(), set(adjacency), set())
        return sorted(set(cliques), key=lambda clique: (-len(clique), clique))

    def _inferred_groups(self, minimum_size: int) -> list[dict[str, Any]]:
        adjacency: dict[str, set[str]] = {}
        pair_claim_ids: dict[tuple[str, str], list[str]] = {}
        for friendship in self._mutual_friendships():
            first, second = friendship["personIDs"]
            adjacency.setdefault(first, set()).add(second)
            adjacency.setdefault(second, set()).add(first)
            pair_claim_ids[(first, second)] = friendship["claimIDs"]

        groups: list[dict[str, Any]] = []
        for clique in self._maximal_cliques(adjacency, minimum_size):
            names = [
                self._people_by_id[person_id]["name"]
                for person_id in clique
                if person_id in self._people_by_id
            ]
            basis_claim_ids: list[str] = []
            for index, first in enumerate(clique):
                for second in clique[index + 1 :]:
                    basis_claim_ids.extend(
                        pair_claim_ids.get(tuple(sorted((first, second))), [])
                    )
            digest = hashlib.sha256("|".join(clique).encode("utf-8")).hexdigest()[:12]
            groups.append(
                {
                    "id": f"inferred-{digest}",
                    "name": "Freundesgruppe: " + ", ".join(names),
                    "memberIDs": list(clique),
                    "members": [
                        self._person_brief(self._people_by_id[person_id])
                        for person_id in clique
                        if person_id in self._people_by_id
                    ],
                    "status": "suggested",
                    "confidence": 0.85,
                    "explanation": (
                        "Vorschlag aus paarweise gegenseitig bestätigten "
                        "Freundschaftsangaben; nicht als Fakt gespeichert."
                    ),
                    "createdAt": None,
                    "source": "inferred",
                    "basisClaimIDs": sorted(set(basis_claim_ids)),
                }
            )
        return groups

    def _decorate_group(self, group: Mapping[str, Any]) -> dict[str, Any]:
        result = dict(group)
        result["members"] = [
            self._person_brief(self._people_by_id[person_id])
            for person_id in group["memberIDs"]
            if person_id in self._people_by_id
        ]
        return result

    def get_groups(
        self,
        person: str | None = None,
        include_inferred: bool = True,
        min_members: int = 3,
    ) -> dict[str, Any]:
        if isinstance(min_members, bool) or not isinstance(min_members, int):
            raise FriendLibraryInputError("minMembers muss eine ganze Zahl sein.")
        if min_members < 2 or min_members > 20:
            raise FriendLibraryInputError("minMembers muss zwischen 2 und 20 liegen.")
        focus = self.find_person(person) if person else None
        focus_id = focus["id"] if focus else None

        persisted = [self._decorate_group(group) for group in self.groups]
        # Inference is deliberately only a fallback. Persisted and suggested
        # groups are therefore never silently mixed.
        inferred = (
            self._inferred_groups(min_members)
            if include_inferred and not persisted
            else []
        )
        if focus_id:
            persisted = [
                group for group in persisted if focus_id in group["memberIDs"]
            ]
            inferred = [group for group in inferred if focus_id in group["memberIDs"]]
        return {
            "person": self._person_brief(focus) if focus else None,
            "persistedGroups": persisted,
            "inferredGroups": inferred,
            "counts": {
                "persisted": len(persisted),
                "inferred": len(inferred),
            },
            "inferencePolicy": (
                "Inferred groups are suggestions generated only when no "
                "persisted groups exist."
            ),
            "metadata": self.metadata,
        }

    def _decorate_media(self, item: Mapping[str, Any]) -> dict[str, Any]:
        result = dict(item)
        result["people"] = [
            self._person_brief(self._people_by_id[person_id])
            for person_id in item["personIDs"]
            if person_id in self._people_by_id
        ]
        result["preview"] = {
            "kind": item["kind"],
            "localPath": item["localPath"],
            "available": item["available"],
        }
        return result

    def get_media_previews(
        self,
        person: str | None = None,
        kind: str | None = None,
        query: str | None = None,
        limit: int = 24,
    ) -> dict[str, Any]:
        limit = self._validated_limit(limit)
        focus = self.find_person(person) if person else None
        focus_id = focus["id"] if focus else None
        normalized_kind = _normalized(kind) if kind else ""
        if normalized_kind and normalized_kind not in {"image", "video"}:
            raise FriendLibraryInputError("kind muss 'image' oder 'video' sein.")
        query_text = _normalized(query) if query else ""

        matches: list[dict[str, Any]] = []
        for item in self.media:
            if focus_id and focus_id not in item["personIDs"]:
                continue
            if normalized_kind and _normalized(item["kind"]) != normalized_kind:
                continue
            searchable = " ".join(
                _normalized(value)
                for value in (
                    item["originalFilename"],
                    item["notes"],
                    *item["tags"],
                    *item["clothingTags"],
                    *item["analysisLabels"],
                )
            )
            if query_text and query_text not in searchable:
                continue
            matches.append(self._decorate_media(item))

        matches.sort(
            key=lambda item: (
                _string(item.get("capturedAt") or item.get("importedAt")),
                item["id"],
            ),
            reverse=True,
        )
        matches = matches[:limit]
        return {
            "person": self._person_brief(focus) if focus else None,
            "kind": kind,
            "query": query,
            "count": len(matches),
            "media": matches,
            "metadata": self.metadata,
        }

    def _observations_for(self, person_id: str) -> dict[str, list[dict[str, Any]]]:
        result: dict[str, list[dict[str, Any]]] = {
            "confirmed": [],
            "suggested": [],
            "other": [],
        }
        for observation in self.observations:
            if observation["personID"] == person_id:
                result[self._status_class(observation["status"])].append(
                    dict(observation)
                )
        for values in result.values():
            values.sort(key=lambda item: (_normalized(item["category"]), item["id"]))
        return result

    def get_person(
        self,
        person: str,
        as_of: str | None = None,
        media_limit: int = 6,
    ) -> dict[str, Any]:
        media_limit = self._validated_limit(media_limit, maximum=24)
        found = self.find_person(person)
        relationships = self.get_relationships(found["id"])
        groups = self.get_groups(found["id"])
        media = self.get_media_previews(found["id"], limit=media_limit)
        observations = self._observations_for(found["id"])
        return {
            "person": dict(found),
            "age": self._age(found, as_of),
            "observations": observations,
            "relationships": relationships,
            "groups": groups,
            "mediaPreviews": media,
            "counts": {
                "relationshipClaims": relationships["counts"]["claims"],
                "mutualFriendships": relationships["counts"]["mutualFriendships"],
                "groups": groups["counts"]["persisted"]
                + groups["counts"]["inferred"],
                "media": media["count"],
                "confirmedObservations": len(observations["confirmed"]),
                "suggestedObservations": len(observations["suggested"]),
            },
            "metadata": self.metadata,
        }

    def _mentioned_person(self, question: str) -> dict[str, Any] | None:
        normalized_question = f" {_normalized(question)} "
        matches: list[tuple[int, str, dict[str, Any]]] = []
        for person in self.people:
            full_name = _normalized(person["name"])
            first_name = full_name.split()[0] if full_name else ""
            candidates = (person["name"], first_name, *person["aliases"])
            for candidate in candidates:
                normalized_candidate = _normalized(candidate)
                if len(normalized_candidate) < 2:
                    continue
                if (
                    f" {normalized_candidate} " in normalized_question
                    or f" {normalized_candidate}s " in normalized_question
                ):
                    matches.append(
                        (-len(normalized_candidate), person["id"], person)
                    )
        if not matches:
            return None
        matches.sort(key=lambda item: (item[0], item[1]))
        best_length = matches[0][0]
        best_people = {item[2]["id"]: item[2] for item in matches if item[0] == best_length}
        if len(best_people) == 1:
            return next(iter(best_people.values()))
        return None

    @staticmethod
    def _contains_any(text: str, candidates: Iterable[str]) -> bool:
        return any(candidate in text for candidate in candidates)

    def query_friend_library(self, question: str, limit: int = 10) -> dict[str, Any]:
        limit = self._validated_limit(limit)
        if not _string(question).strip():
            raise FriendLibraryInputError("question darf nicht leer sein.")
        normalized_question = _normalized(question)
        person = self._mentioned_person(question)

        if self._contains_any(
            normalized_question, ("gruppe", "gruppen", "clique", "friend group")
        ):
            intent = "groups"
        elif self._contains_any(
            normalized_question, ("foto", "fotos", "photo", "video", "bild")
        ):
            intent = "media"
        elif self._contains_any(
            normalized_question,
            ("tragt", "traegt", "kleidung", "outfit", "style", "wear"),
        ):
            intent = "style"
        elif self._contains_any(
            normalized_question,
            (
                "social media",
                "socialmedia",
                "instagram",
                "tiktok",
                "linkedin",
                "facebook",
                "youtube",
                "mastodon",
                "bluesky",
                "webseite",
                "website",
                "homepage",
                "link",
                "handle",
                "username",
            ),
        ):
            intent = "links"
        elif self._contains_any(
            normalized_question,
            ("befreundet", "freund", "freunde", "relationship"),
        ):
            intent = "relationships"
        elif self._contains_any(
            normalized_question, ("wie alt", "alter", "age", "geburt")
        ):
            intent = "age"
        elif self._contains_any(
            normalized_question,
            ("wo wohnt", "wohnort", "location", "lebt", "wohn"),
        ):
            intent = "location"
        elif self._contains_any(
            normalized_question,
            ("gemut", "gemuet", "temperament", "personlichkeit", "personality"),
        ):
            intent = "temperament"
        else:
            intent = "profile"

        if person is None:
            if intent == "groups":
                groups = self.get_groups()
                return {
                    "question": question,
                    "matchedIntent": intent,
                    "answer": (
                        f"{groups['counts']['persisted']} gespeicherte und "
                        f"{groups['counts']['inferred']} vorgeschlagene Gruppen gefunden."
                    ),
                    "evidence": groups,
                    "metadata": self.metadata,
                }
            if intent in {"media", "style"}:
                media = self.get_media_previews(
                    query=None if intent == "media" else normalized_question, limit=limit
                )
                return {
                    "question": question,
                    "matchedIntent": intent,
                    "answer": f"{media['count']} passende Medien gefunden.",
                    "evidence": media,
                    "metadata": self.metadata,
                }
            search = self.search_people(question, limit=limit)
            return {
                "question": question,
                "matchedIntent": intent,
                "answer": (
                    "Keine Person wurde eindeutig erkannt."
                    if not search["people"]
                    else f"{search['count']} mögliche Personen gefunden."
                ),
                "evidence": search,
                "metadata": self.metadata,
            }

        profile = self.get_person(person["id"], media_limit=min(limit, 24))
        name = person["name"] or person["id"]
        evidence: Any

        if intent == "age":
            age = profile["age"]
            if age and age["years"] is not None:
                answer = (
                    f"{name} ist am {age['asOf']} {age['years']} Jahre alt "
                    f"(berechnet aus dem gespeicherten Geburtstag)."
                )
            else:
                answer = f"Für {name} ist kein auswertbarer Geburtstag gespeichert."
            evidence = {"person": self._person_brief(person), "age": age}
        elif intent == "location":
            location = person["location"]
            answer = (
                f"{name} wohnt laut gespeichertem Profil in {location}."
                if location
                else f"Für {name} ist kein Wohnort gespeichert."
            )
            evidence = {
                "person": self._person_brief(person),
                "location": location,
            }
        elif intent == "links":
            links = [dict(link) for link in person["links"]]
            labels: list[str] = []
            for link in links:
                label = (
                    link["platform"]
                    or link["title"]
                    or link["handle"]
                    or link["url"]
                    or link["kind"]
                    or "Link"
                )
                if link["handle"] and link["handle"] not in label:
                    label += f" ({link['handle']})"
                if not link["confirmed"]:
                    label += " [unbestätigt]"
                labels.append(label)
            answer = (
                f"Für {name} sind gespeichert: " + ", ".join(labels) + "."
                if labels
                else f"Für {name} sind keine Social-Media- oder Webseitenlinks gespeichert."
            )
            evidence = {
                "person": self._person_brief(person),
                "links": links,
                "counts": {
                    "total": len(links),
                    "confirmed": sum(link["confirmed"] for link in links),
                    "unconfirmed": sum(not link["confirmed"] for link in links),
                },
            }
        elif intent == "relationships":
            relationships = profile["relationships"]
            friend_names: list[str] = []
            for friendship in relationships["mutualFriendships"]:
                friend_names.extend(
                    candidate["name"]
                    for candidate in friendship["people"]
                    if candidate["id"] != person["id"]
                )
            friend_names = sorted(set(friend_names), key=_normalized)
            answer = (
                f"{name} ist gegenseitig bestätigt befreundet mit "
                + ", ".join(friend_names)
                + "."
                if friend_names
                else f"Für {name} gibt es keine gegenseitig bestätigte Freundschaft."
            )
            evidence = relationships
        elif intent == "groups":
            groups = profile["groups"]
            group_names = [
                group["name"]
                for group in groups["persistedGroups"] + groups["inferredGroups"]
            ]
            answer = (
                f"Für {name} gefunden: " + ", ".join(group_names) + "."
                if group_names
                else f"Für {name} wurde keine Gruppe gefunden."
            )
            if groups["inferredGroups"] and not groups["persistedGroups"]:
                answer += " Die angezeigte Gruppe ist nur ein Vorschlag aus Beziehungen."
            evidence = groups
        elif intent in {"media", "style"}:
            media = profile["mediaPreviews"]
            clothing = Counter(
                tag
                for item in media["media"]
                for tag in item.get("clothingTags", [])
                if tag
            )
            if intent == "style":
                common = [tag for tag, _count in clothing.most_common(5)]
                answer = (
                    f"Bei {name} kommen in den gespeicherten Medien häufig vor: "
                    + ", ".join(common)
                    + "."
                    if common
                    else f"Für {name} sind keine Kleidungsmerkmale gespeichert."
                )
            else:
                answer = f"{media['count']} Medienvorschauen für {name} gefunden."
            evidence = {
                "person": self._person_brief(person),
                "commonClothingTags": [
                    {"tag": tag, "count": count}
                    for tag, count in clothing.most_common(5)
                ],
                "mediaPreviews": media,
            }
        elif intent == "temperament":
            confirmed = [
                observation
                for observation in profile["observations"]["confirmed"]
                if _normalized(observation["category"])
                in {"gemut", "gemuet", "personality", "temperament"}
            ]
            suggested = [
                observation
                for observation in profile["observations"]["suggested"]
                if _normalized(observation["category"])
                in {"gemut", "gemuet", "personality", "temperament"}
            ]
            tags = person["temperamentTags"]
            answer = (
                f"{name} ist im Profil beschrieben als: {', '.join(tags)}."
                if tags
                else f"Für {name} sind keine bestätigten Temperament-Tags gespeichert."
            )
            if suggested:
                answer += " Zusätzlich gibt es klar getrennte, unbestätigte Vorschläge."
            evidence = {
                "person": self._person_brief(person),
                "confirmedObservations": confirmed,
                "suggestedObservations": suggested,
            }
        else:
            parts = [name]
            if person["summary"]:
                parts.append(person["summary"])
            if person["location"]:
                parts.append(f"Wohnort: {person['location']}")
            if person["temperamentTags"]:
                parts.append("Gemüt: " + ", ".join(person["temperamentTags"]))
            if person["interests"]:
                parts.append("Interessen: " + ", ".join(person["interests"]))
            if person["links"]:
                link_labels = [
                    (
                        link["platform"]
                        or link["title"]
                        or link["handle"]
                        or link["url"]
                    )
                    + ("" if link["confirmed"] else " [unbestätigt]")
                    for link in person["links"]
                ]
                parts.append("Links: " + ", ".join(filter(None, link_labels)))
            answer = ". ".join(part.rstrip(".") for part in parts) + "."
            evidence = profile

        return {
            "question": question,
            "matchedIntent": intent,
            "matchedPerson": self._person_brief(person),
            "answer": answer,
            "evidence": evidence,
            "metadata": self.metadata,
        }


READ_ONLY_ANNOTATIONS = {
    "readOnlyHint": True,
    "destructiveHint": False,
    "idempotentHint": True,
    "openWorldHint": False,
}
WRITE_ANNOTATIONS = {
    "readOnlyHint": False,
    "destructiveHint": False,
    "idempotentHint": False,
    "openWorldHint": False,
}
IDEMPOTENT_WRITE_ANNOTATIONS = WRITE_ANNOTATIONS | {"idempotentHint": True}
GENERIC_OUTPUT_SCHEMA = {"type": "object", "additionalProperties": True}

TOOLS: list[dict[str, Any]] = [
    {
        "name": "search_people",
        "title": "Personen suchen",
        "description": (
            "Sucht deterministisch nach Namen, Alias, Ort, Zusammenfassung, "
            "Temperament, Interessen oder gespeicherten Social-Media- und "
            "Webseitenlinks in der lokalen Freundebibliothek."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "Suchtext; leer listet alle."},
                "limit": {
                    "type": "integer",
                    "minimum": 1,
                    "maximum": 100,
                    "default": 20,
                },
            },
            "required": ["query"],
            "additionalProperties": False,
        },
        "outputSchema": GENERIC_OUTPUT_SCHEMA,
        "annotations": READ_ONLY_ANNOTATIONS,
        "execution": {"taskSupport": "forbidden"},
    },
    {
        "name": "get_person",
        "title": "Personenprofil laden",
        "description": (
            "Lädt ein Personenprofil mit Alter, bestätigten und vorgeschlagenen "
            "Beobachtungen, Beziehungen, Gruppen, gespeicherten Links und wenigen "
            "Medienvorschauen."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "person": {"type": "string", "description": "Personen-ID, Name oder Alias."},
                "asOf": {
                    "type": "string",
                    "description": "Optionales ISO-Datum für die Altersberechnung.",
                },
                "mediaLimit": {
                    "type": "integer",
                    "minimum": 1,
                    "maximum": 24,
                    "default": 6,
                },
            },
            "required": ["person"],
            "additionalProperties": False,
        },
        "outputSchema": GENERIC_OUTPUT_SCHEMA,
        "annotations": READ_ONLY_ANNOTATIONS,
        "execution": {"taskSupport": "forbidden"},
    },
    {
        "name": "get_relationships",
        "title": "Beziehungen laden",
        "description": (
            "Lädt gerichtete Beziehungsangaben und erkennt daraus gegenseitig "
            "bestätigte Freundschaften, ohne Daten zu verändern."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "person": {"type": "string", "description": "Optionale Personen-ID/Name."},
                "includeUnconfirmed": {
                    "type": "boolean",
                    "default": True,
                    "description": "Auch unbestätigte Angaben anzeigen.",
                },
            },
            "additionalProperties": False,
        },
        "outputSchema": GENERIC_OUTPUT_SCHEMA,
        "annotations": READ_ONLY_ANNOTATIONS,
        "execution": {"taskSupport": "forbidden"},
    },
    {
        "name": "get_groups",
        "title": "Freundesgruppen laden",
        "description": (
            "Lädt gespeicherte Gruppen. Falls gar keine gespeichert sind, können "
            "aus paarweise gegenseitigen Freundschaften klar markierte Vorschläge "
            "abgeleitet werden."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "person": {"type": "string", "description": "Optionale Personen-ID/Name."},
                "includeInferred": {"type": "boolean", "default": True},
                "minMembers": {
                    "type": "integer",
                    "minimum": 2,
                    "maximum": 20,
                    "default": 3,
                },
            },
            "additionalProperties": False,
        },
        "outputSchema": GENERIC_OUTPUT_SCHEMA,
        "annotations": READ_ONLY_ANNOTATIONS,
        "execution": {"taskSupport": "forbidden"},
    },
    {
        "name": "get_media_previews",
        "title": "Medienvorschauen laden",
        "description": (
            "Liefert Metadaten und sichere lokale Pfade zu Bildern oder Videos. "
            "Binärdateien und die Bibliothek werden nicht verändert."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "person": {"type": "string", "description": "Optionale Personen-ID/Name."},
                "kind": {"type": "string", "enum": ["image", "video"]},
                "query": {"type": "string", "description": "Optionaler Tag-/Label-Filter."},
                "limit": {
                    "type": "integer",
                    "minimum": 1,
                    "maximum": 100,
                    "default": 24,
                },
            },
            "additionalProperties": False,
        },
        "outputSchema": GENERIC_OUTPUT_SCHEMA,
        "annotations": READ_ONLY_ANNOTATIONS,
        "execution": {"taskSupport": "forbidden"},
    },
    {
        "name": "query_friend_library",
        "title": "Freundebibliothek fragen",
        "description": (
            "Beantwortet kompakte deutsche oder englische Fragen zu Personen, "
            "Alter, Wohnort, Beziehungen, Gruppen, Temperament, Kleidung, Medien "
            "und gespeicherten Social-Media- oder Webseitenlinks."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "question": {"type": "string", "minLength": 1},
                "limit": {
                    "type": "integer",
                    "minimum": 1,
                    "maximum": 100,
                    "default": 10,
                },
            },
            "required": ["question"],
            "additionalProperties": False,
        },
        "outputSchema": GENERIC_OUTPUT_SCHEMA,
        "annotations": READ_ONLY_ANNOTATIONS,
        "execution": {"taskSupport": "forbidden"},
    },
    {
        "name": "save_person",
        "title": "Person speichern",
        "description": (
            "Legt eine Person an oder aktualisiert ausgewählte Profilfelder. Vor "
            "einem Update zuerst suchen und die gefundene ID als person übergeben."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "person": {"type": "string", "description": "Nur bei Update: ID, Name oder Alias."},
                "name": {"type": "string", "minLength": 1},
                "aliases": {"type": "array", "items": {"type": "string"}},
                "birthday": {"type": ["string", "null"], "description": "ISO-Datum oder null."},
                "location": {"type": ["string", "null"]},
                "summary": {"type": "string"},
                "temperamentTags": {"type": "array", "items": {"type": "string"}},
                "interests": {"type": "array", "items": {"type": "string"}},
                "profileDetails": {
                    "type": "object",
                    "description": (
                        "Steckbrief-Felder als Schlüssel mit Listen von Werten, "
                        "z. B. favoriteColors: [Blau]."
                    ),
                    "additionalProperties": {
                        "type": "array",
                        "items": {"type": "string"},
                    },
                },
            },
            "additionalProperties": False,
        },
        "outputSchema": GENERIC_OUTPUT_SCHEMA,
        "annotations": IDEMPOTENT_WRITE_ANNOTATIONS,
        "execution": {"taskSupport": "forbidden"},
    },
    {
        "name": "save_profile_link",
        "title": "Profil-Link speichern",
        "description": (
            "Speichert oder aktualisiert einen öffentlichen HTTPS-Profil-Link. "
            "Neue Links sind standardmäßig unbestätigt."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "person": {"type": "string"},
                "url": {"type": "string", "minLength": 1},
                "linkID": {"type": "string"},
                "platform": {
                    "type": "string",
                    "enum": [
                        "website", "instagram", "tiktok", "youtube", "linkedin",
                        "x", "facebook", "snapchat", "threads", "mastodon",
                        "github", "other"
                    ],
                    "default": "website",
                },
                "title": {"type": "string"},
                "handle": {"type": "string"},
                "confirmed": {"type": "boolean", "default": False},
            },
            "required": ["person", "url"],
            "additionalProperties": False,
        },
        "outputSchema": GENERIC_OUTPUT_SCHEMA,
        "annotations": IDEMPOTENT_WRITE_ANNOTATIONS,
        "execution": {"taskSupport": "forbidden"},
    },
    {
        "name": "save_relationship",
        "title": "Beziehung speichern",
        "description": (
            "Legt eine gerichtete Beziehungsangabe an oder aktualisiert sie. "
            "reciprocal=true speichert beide Richtungen; bei Familie wird die "
            "passende Gegenrolle verwendet. Familienverbindungen bleiben paarweise."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "fromPerson": {"type": "string"},
                "toPerson": {"type": "string"},
                "kind": {
                    "type": "string",
                    "enum": ["friendship", "family", "romantic", "school", "work", "acquaintance", "other"],
                    "default": "friendship",
                },
                "familyRole": {
                    "type": "string",
                    "enum": [
                        "familyMember", "parent", "child", "sibling",
                        "grandparent", "grandchild", "auntUncle", "nieceNephew",
                        "cousin", "spouse", "stepfamily", "inLaw",
                    ],
                    "description": "Nur bei kind=family: Rolle der Zielperson aus Sicht der Ausgangsperson.",
                    "default": "familyMember",
                },
                "status": {
                    "type": "string",
                    "enum": ["claimed", "confirmed", "disputed", "rejected", "ended"],
                    "default": "claimed",
                },
                "source": {
                    "type": "string",
                    "enum": ["manual", "personStatement", "mediaAnalysis", "inferred", "imported"],
                    "default": "manual",
                },
                "notes": {"type": "string"},
                "reciprocal": {"type": "boolean", "default": False},
            },
            "required": ["fromPerson", "toPerson"],
            "additionalProperties": False,
        },
        "outputSchema": GENERIC_OUTPUT_SCHEMA,
        "annotations": IDEMPOTENT_WRITE_ANNOTATIONS,
        "execution": {"taskSupport": "forbidden"},
    },
    {
        "name": "save_observation",
        "title": "Beobachtung speichern",
        "description": (
            "Legt eine belegte Beobachtung an oder aktualisiert sie. Neue "
            "Beobachtungen sind standardmäßig unbestätigt."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "person": {"type": "string"},
                "observationID": {"type": "string"},
                "category": {
                    "type": "string",
                    "enum": ["identity", "location", "personality", "clothing", "appearance", "interest", "preference", "habit", "biography", "other"],
                },
                "value": {"type": "string", "minLength": 1},
                "status": {
                    "type": "string",
                    "enum": ["unverified", "likely", "confirmed", "disputed", "archived"],
                    "default": "unverified",
                },
                "confidence": {"type": "number", "minimum": 0, "maximum": 1, "default": 0.5},
                "source": {
                    "type": "string",
                    "enum": ["manual", "personStatement", "mediaAnalysis", "inferred", "imported"],
                    "default": "manual",
                },
                "evidenceMediaIDs": {"type": "array", "items": {"type": "string"}},
            },
            "required": ["person", "category", "value"],
            "additionalProperties": False,
        },
        "outputSchema": GENERIC_OUTPUT_SCHEMA,
        "annotations": WRITE_ANNOTATIONS,
        "execution": {"taskSupport": "forbidden"},
    },
]

_TOOL_ARGUMENTS: dict[str, set[str]] = {
    "search_people": {"query", "limit"},
    "get_person": {"person", "asOf", "mediaLimit"},
    "get_relationships": {"person", "includeUnconfirmed"},
    "get_groups": {"person", "includeInferred", "minMembers"},
    "get_media_previews": {"person", "kind", "query", "limit"},
    "query_friend_library": {"question", "limit"},
    "save_person": {
        "person", "name", "aliases", "birthday", "location", "summary",
        "temperamentTags", "interests", "profileDetails",
    },
    "save_profile_link": {
        "person", "url", "linkID", "platform", "title", "handle", "confirmed",
    },
    "save_relationship": {
        "fromPerson", "toPerson", "kind", "familyRole", "status", "source", "notes",
        "reciprocal",
    },
    "save_observation": {
        "person", "observationID", "category", "value", "status", "confidence",
        "source", "evidenceMediaIDs",
    },
}


def _validate_tool_arguments(name: str, arguments: Any) -> dict[str, Any]:
    if arguments is None:
        arguments = {}
    if not isinstance(arguments, Mapping):
        raise FriendLibraryInputError("arguments muss ein JSON-Objekt sein.")
    copied = dict(arguments)
    unexpected = sorted(set(copied) - _TOOL_ARGUMENTS[name])
    if unexpected:
        raise FriendLibraryInputError(
            "Unbekannte Argumente: " + ", ".join(unexpected) + "."
        )
    return copied


def _required_string(arguments: Mapping[str, Any], key: str) -> str:
    value = arguments.get(key)
    if not isinstance(value, str) or not value.strip():
        raise FriendLibraryInputError(f"{key} muss eine nicht leere Zeichenkette sein.")
    return value


def _optional_string(arguments: Mapping[str, Any], key: str) -> str | None:
    value = arguments.get(key)
    if value is None:
        return None
    if not isinstance(value, str):
        raise FriendLibraryInputError(f"{key} muss eine Zeichenkette sein.")
    return value


def _optional_bool(arguments: Mapping[str, Any], key: str, default: bool) -> bool:
    value = arguments.get(key, default)
    if not isinstance(value, bool):
        raise FriendLibraryInputError(f"{key} muss true oder false sein.")
    return value


def _optional_int(arguments: Mapping[str, Any], key: str, default: int) -> int:
    value = arguments.get(key, default)
    if isinstance(value, bool) or not isinstance(value, int):
        raise FriendLibraryInputError(f"{key} muss eine ganze Zahl sein.")
    return value


def call_tool(
    library: FriendLibrary, name: str, arguments: Mapping[str, Any] | None
) -> dict[str, Any]:
    """Call one FreundeBlick tool and return structured JSON data."""

    if name not in _TOOL_ARGUMENTS:
        raise KeyError(name)
    values = _validate_tool_arguments(name, arguments)
    if name == "search_people":
        return library.search_people(
            _required_string_allow_empty(values, "query"),
            _optional_int(values, "limit", 20),
        )
    if name == "get_person":
        return library.get_person(
            _required_string(values, "person"),
            _optional_string(values, "asOf"),
            _optional_int(values, "mediaLimit", 6),
        )
    if name == "get_relationships":
        return library.get_relationships(
            _optional_string(values, "person"),
            _optional_bool(values, "includeUnconfirmed", True),
        )
    if name == "get_groups":
        return library.get_groups(
            _optional_string(values, "person"),
            _optional_bool(values, "includeInferred", True),
            _optional_int(values, "minMembers", 3),
        )
    if name == "get_media_previews":
        return library.get_media_previews(
            _optional_string(values, "person"),
            _optional_string(values, "kind"),
            _optional_string(values, "query"),
            _optional_int(values, "limit", 24),
        )
    if name == "save_person":
        return library.save_person(values)
    if name == "save_profile_link":
        if not isinstance(values.get("confirmed", False), bool):
            raise FriendLibraryInputError("confirmed muss true oder false sein.")
        return library.save_profile_link(values)
    if name == "save_relationship":
        if not isinstance(values.get("reciprocal", False), bool):
            raise FriendLibraryInputError("reciprocal muss true oder false sein.")
        return library.save_relationship(values)
    if name == "save_observation":
        return library.save_observation(values)
    return library.query_friend_library(
        _required_string(values, "question"),
        _optional_int(values, "limit", 10),
    )


def _required_string_allow_empty(arguments: Mapping[str, Any], key: str) -> str:
    value = arguments.get(key)
    if not isinstance(value, str):
        raise FriendLibraryInputError(f"{key} muss eine Zeichenkette sein.")
    return value


def _tool_result(data: Mapping[str, Any]) -> dict[str, Any]:
    serialized = json.dumps(
        data, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    )
    return {
        "content": [{"type": "text", "text": serialized}],
        "structuredContent": dict(data),
        "isError": False,
    }


def _tool_error(error: Exception) -> dict[str, Any]:
    return {
        "content": [{"type": "text", "text": str(error)}],
        "structuredContent": {"error": str(error)},
        "isError": True,
    }


def _jsonrpc_result(request_id: Any, result: Mapping[str, Any]) -> dict[str, Any]:
    return {"jsonrpc": "2.0", "id": request_id, "result": dict(result)}


def _jsonrpc_error(
    request_id: Any, code: int, message: str, data: Any = None
) -> dict[str, Any]:
    error: dict[str, Any] = {"code": code, "message": message}
    if data is not None:
        error["data"] = data
    return {"jsonrpc": "2.0", "id": request_id, "error": error}


class MCPServer:
    """Small synchronous MCP server suitable for Codex stdio integration."""

    def __init__(self, library: FriendLibrary):
        self.library = library

    def handle(self, message: Any) -> dict[str, Any] | None:
        if not isinstance(message, Mapping):
            return _jsonrpc_error(None, -32600, "Invalid Request")

        request_id = message.get("id")
        has_id = "id" in message
        if message.get("jsonrpc") != "2.0" or not isinstance(
            message.get("method"), str
        ):
            return _jsonrpc_error(request_id if has_id else None, -32600, "Invalid Request")

        method = message["method"]
        params = message.get("params", {})
        if not isinstance(params, Mapping):
            if not has_id:
                return None
            return _jsonrpc_error(request_id, -32602, "Invalid params")

        if not has_id:
            # MCP lifecycle/cancellation notifications never receive responses.
            return None

        if method == "initialize":
            requested_version = params.get("protocolVersion")
            protocol_version = (
                requested_version
                if requested_version in SUPPORTED_PROTOCOL_VERSIONS
                else PROTOCOL_VERSION
            )
            return _jsonrpc_result(
                request_id,
                {
                    "protocolVersion": protocol_version,
                    "capabilities": {"tools": {"listChanged": False}},
                    "serverInfo": {
                        "name": SERVER_NAME,
                        "title": "FreundeBlick Bridge",
                        "version": SERVER_VERSION,
                        "description": (
                            "Lokaler Lese- und Schreibzugriff auf friends.json."
                        ),
                    },
                    "instructions": (
                        "Schreibwerkzeuge speichern atomar und löschen keine Daten. "
                        "Neue Beobachtungen bleiben standardmäßig unbestätigt. "
                        "Inferred groups and suggested observations are not confirmed facts."
                    ),
                },
            )

        if method == "ping":
            return _jsonrpc_result(request_id, {})

        if method == "tools/list":
            cursor = params.get("cursor")
            if cursor not in (None, ""):
                return _jsonrpc_error(
                    request_id, -32602, "Invalid cursor: tool list has one page."
                )
            return _jsonrpc_result(request_id, {"tools": TOOLS})

        if method == "tools/call":
            name = params.get("name")
            arguments = params.get("arguments", {})
            if not isinstance(name, str):
                return _jsonrpc_error(
                    request_id, -32602, "Tool name must be a string."
                )
            if name not in _TOOL_ARGUMENTS:
                return _jsonrpc_error(
                    request_id, -32602, f"Unknown tool: {name}"
                )
            if not isinstance(arguments, Mapping):
                return _jsonrpc_error(
                    request_id, -32602, "Tool arguments must be an object."
                )
            try:
                # The app also writes this file. Reload before every tool call so
                # a long-running MCP process never answers from a stale snapshot.
                self.library = FriendLibrary.from_path(self.library.data_path)
                result = call_tool(self.library, name, arguments)
            except FriendLibraryError as error:
                return _jsonrpc_result(request_id, _tool_error(error))
            except Exception:
                # Do not leak local paths or implementation details over MCP.
                return _jsonrpc_result(
                    request_id,
                    _tool_error(
                        FriendLibraryError(
                            "Interner Fehler beim Zugriff auf die Freundebibliothek."
                        )
                    ),
                )
            return _jsonrpc_result(request_id, _tool_result(result))

        return _jsonrpc_error(request_id, -32601, f"Method not found: {method}")


def serve_stdio(library: FriendLibrary) -> None:
    """Serve newline-delimited UTF-8 JSON-RPC until stdin reaches EOF."""

    server = MCPServer(library)
    for raw_line in sys.stdin.buffer:
        if not raw_line.strip():
            continue
        try:
            message = json.loads(raw_line)
        except (UnicodeDecodeError, json.JSONDecodeError):
            response = _jsonrpc_error(None, -32700, "Parse error")
        else:
            response = server.handle(message)
        if response is not None:
            encoded = json.dumps(
                response, ensure_ascii=False, sort_keys=True, separators=(",", ":")
            )
            sys.stdout.write(encoded + "\n")
            sys.stdout.flush()


def build_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="FreundeBlick MCP stdio server"
    )
    parser.add_argument(
        "--data",
        metavar="PATH",
        help=(
            "Pfad zu friends.json. Standard: FREUNDEBLICK_DATA_FILE, "
            "FREUNDEBLICK_DATA_DIR oder FreundeblickData/friends.json."
        ),
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    arguments = build_argument_parser().parse_args(argv)
    try:
        library = FriendLibrary.from_path(arguments.data)
    except FriendLibraryError as error:
        print(str(error), file=sys.stderr)
        return 2
    serve_stdio(library)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
