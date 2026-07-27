from __future__ import annotations

import copy
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import unittest
import uuid
from pathlib import Path
from unittest.mock import patch


WORKSPACE = Path(__file__).resolve().parents[1]
TOOLS_DIRECTORY = WORKSPACE / "Tools"
if str(TOOLS_DIRECTORY) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIRECTORY))

from freundeblick_mcp import (  # noqa: E402
    MCPServer,
    PROTOCOL_VERSION,
    TOOLS,
    FriendLibrary,
    FriendLibraryInputError,
    call_tool,
)


def sample_payload() -> dict:
    people = [
        {
            "id": "person-ada",
            "name": "Ada Beispiel",
            "aliases": ["Ädi"],
            "birthday": "2000-02-29T00:00:00Z",
            "location": "Nordstadt",
            "summary": "Beobachtet erst und redet dann.",
            "temperamentTags": ["ruhig", "aufmerksam"],
            "interests": ["Keramik", "Wandern"],
            "avatarMediaID": "media-ada",
            "links": [
                {
                    "id": "link-ada-instagram",
                    "kind": "socialMedia",
                    "platform": "Instagram",
                    "title": "Adas Keramik",
                    "url": "https://www.instagram.com/ada.beispiel/",
                    "handle": "@ada.beispiel",
                    "confirmed": True,
                    "createdAt": "2026-01-01T11:00:00Z",
                },
                {
                    "id": "link-ada-website",
                    "kind": "website",
                    "platform": "",
                    "title": "Keramik-Portfolio",
                    "url": "https://ada.example/keramik",
                    "handle": "",
                    "confirmed": False,
                    "createdAt": "2026-01-01T12:00:00Z",
                },
            ],
            "createdAt": "2026-01-01T10:00:00Z",
        },
        {
            "id": "person-bo",
            "name": "Bo Beispiel",
            "aliases": ["Bobo"],
            "birthday": None,
            "location": "Südstadt",
            "summary": "Plant gern gemeinsame Ausflüge.",
            "temperamentTags": ["gesellig"],
            "interests": ["Kochen"],
            "avatarMediaID": None,
            "createdAt": "2026-01-02T10:00:00Z",
        },
        {
            "id": "person-cleo",
            "name": "Cleo Beispiel",
            "aliases": [],
            "birthday": "1999-12-01T00:00:00Z",
            "location": None,
            "summary": "Mag kleine Konzerte.",
            "temperamentTags": ["neugierig"],
            "interests": ["Musik"],
            "avatarMediaID": None,
            "createdAt": "2026-01-03T10:00:00Z",
        },
    ]

    claim_pairs = (
        ("person-ada", "person-bo"),
        ("person-ada", "person-cleo"),
        ("person-bo", "person-cleo"),
    )
    claims = []
    claim_number = 0
    for first, second in claim_pairs:
        for source, target in ((first, second), (second, first)):
            claim_number += 1
            claims.append(
                {
                    "id": f"claim-{claim_number}",
                    "fromPersonID": source,
                    "toPersonID": target,
                    "kind": "friendship",
                    # Swift's default is "claimed"; reciprocal claimed entries
                    # must still support (clearly marked) inference.
                    "status": "claimed" if claim_number <= 2 else "confirmed",
                    "source": "manual",
                    "notes": "",
                    "createdAt": f"2026-02-{claim_number:02d}T10:00:00Z",
                }
            )
    claims.append(
        {
            "id": "claim-pending",
            "fromPersonID": "person-ada",
            "toPersonID": "person-bo",
            "kind": "colleague",
            "status": "suggested",
            "source": "import",
            "notes": "Noch prüfen",
            "createdAt": "2026-03-01T10:00:00Z",
        }
    )

    return {
        "schemaVersion": 1,
        "people": people,
        "relationshipClaims": claims,
        "groups": [],
        "media": [
            {
                "id": "media-ada",
                "storedFilename": "ada.jpg",
                "originalFilename": "IMG_0001.JPG",
                "kind": "image",
                "personIDs": ["person-ada"],
                "importedAt": "2026-04-02T10:00:00Z",
                "capturedAt": "2026-04-01T10:00:00Z",
                "tags": ["Park"],
                "clothingTags": ["grüne Jacke", "Sneaker"],
                "notes": "Spaziergang",
                "analysisLabels": ["outdoor"],
            },
            {
                "id": "media-unsafe",
                "storedFilename": "../../private.txt",
                "originalFilename": "private.txt",
                "kind": "image",
                "personIDs": ["person-ada"],
                "importedAt": "2026-04-03T10:00:00Z",
                "capturedAt": None,
                "tags": [],
                "clothingTags": [],
                "notes": "",
                "analysisLabels": [],
            },
        ],
        "observations": [
            {
                "id": "observation-confirmed",
                "personID": "person-ada",
                "category": "temperament",
                "value": "ruhig in großen Gruppen",
                "status": "confirmed",
                "confidence": 1.0,
                "source": "manual",
                "evidenceMediaIDs": [],
                "createdAt": "2026-04-04T10:00:00Z",
            },
            {
                "id": "observation-suggested",
                "personID": "person-ada",
                "category": "clothing",
                "value": "trägt oft Grün",
                "status": "suggested",
                "confidence": 0.7,
                "source": "media-analysis",
                "evidenceMediaIDs": ["media-ada"],
                "createdAt": "2026-04-05T10:00:00Z",
            },
        ],
        "lastUpdated": "2026-07-26T12:00:00Z",
    }


class LibraryTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.data_directory = Path(self.temporary_directory.name) / "FreundeblickData"
        self.media_directory = self.data_directory / "Media"
        self.media_directory.mkdir(parents=True)
        self.data_path = self.data_directory / "friends.json"
        self.payload = sample_payload()
        self.data_path.write_text(
            json.dumps(self.payload, ensure_ascii=False, sort_keys=True),
            encoding="utf-8",
        )
        (self.media_directory / "ada.jpg").write_bytes(b"synthetic-image-fixture")
        self.library = FriendLibrary.from_path(self.data_path)

    def test_primary_camel_case_schema_loads(self) -> None:
        self.assertEqual(self.library.metadata["schemaVersion"], 1)
        self.assertEqual(len(self.library.people), 3)
        self.assertEqual(len(self.library.relationship_claims), 7)
        self.assertEqual(len(self.library.media), 2)
        self.assertEqual(
            [link["id"] for link in self.library.people[0]["links"]],
            ["link-ada-instagram", "link-ada-website"],
        )
        self.assertFalse(self.library.metadata["readOnly"])

    def test_database_leaf_symlink_is_rejected(self) -> None:
        symlink_path = self.data_directory / "linked-friends.json"
        symlink_path.symlink_to(self.data_path)

        with self.assertRaisesRegex(
            FriendLibraryInputError,
            "symbolische Verknüpfung",
        ):
            FriendLibrary.from_path(symlink_path)

    def test_legacy_people_without_links_load_with_an_empty_list(self) -> None:
        result = self.library.get_person("Bo Beispiel")
        self.assertEqual(result["person"]["links"], [])

    def test_search_is_accent_insensitive_and_deterministic(self) -> None:
        first = self.library.search_people("Adi")
        second = self.library.search_people("Adi")
        self.assertEqual(first, second)
        self.assertEqual(first["people"][0]["id"], "person-ada")

    def test_search_can_use_profile_fields(self) -> None:
        result = self.library.search_people("Wer interessiert sich für Keramik?")
        self.assertEqual([person["id"] for person in result["people"]], ["person-ada"])

    def test_search_can_use_link_platform_handle_title_and_url(self) -> None:
        for query in (
            "Instagram",
            "ada.beispiel",
            "Keramik-Portfolio",
            "ada.example/keramik",
        ):
            with self.subTest(query=query):
                result = self.library.search_people(query)
                self.assertEqual(
                    result["people"][0]["id"],
                    "person-ada",
                )
                self.assertEqual(
                    result["people"][0]["links"][0]["id"],
                    "link-ada-instagram",
                )

    def test_get_person_calculates_age_and_separates_suggestions(self) -> None:
        result = self.library.get_person(
            "Ädi", as_of="2026-07-26", media_limit=10
        )
        self.assertEqual(result["person"]["id"], "person-ada")
        self.assertEqual(result["age"]["years"], 26)
        self.assertEqual(
            [item["id"] for item in result["observations"]["confirmed"]],
            ["observation-confirmed"],
        )
        self.assertEqual(
            [item["id"] for item in result["observations"]["suggested"]],
            ["observation-suggested"],
        )
        self.assertEqual(len(result["person"]["links"]), 2)
        self.assertTrue(result["person"]["links"][0]["confirmed"])
        self.assertFalse(result["person"]["links"][1]["confirmed"])

    def test_relationships_identify_only_reciprocal_friendships(self) -> None:
        result = self.library.get_relationships("person-ada")
        other_ids = {
            person_id
            for friendship in result["mutualFriendships"]
            for person_id in friendship["personIDs"]
            if person_id != "person-ada"
        }
        self.assertEqual(other_ids, {"person-bo", "person-cleo"})
        self.assertTrue(
            all(item["status"] == "confirmedByBoth" for item in result["mutualFriendships"])
        )

    def test_inferred_group_is_stable_and_marked_as_suggestion(self) -> None:
        first = self.library.get_groups()
        second = FriendLibrary.from_path(self.data_path).get_groups()
        self.assertEqual(first, second)
        self.assertEqual(first["counts"], {"persisted": 0, "inferred": 1})
        group = first["inferredGroups"][0]
        self.assertEqual(
            group["memberIDs"], ["person-ada", "person-bo", "person-cleo"]
        )
        self.assertEqual(group["status"], "suggested")
        self.assertEqual(group["source"], "inferred")
        self.assertTrue(group["id"].startswith("inferred-"))
        self.assertIn("nicht als Fakt", group["explanation"])

    def test_unrelated_persisted_group_does_not_suppress_inference(self) -> None:
        payload = copy.deepcopy(self.payload)
        payload["groups"] = [
            {
                "id": "group-saved",
                "name": "Gespeicherte Gruppe",
                "memberIDs": ["person-ada", "person-bo"],
                "status": "confirmed",
                "confidence": 1.0,
                "explanation": "Manuell gespeichert.",
                "createdAt": "2026-05-01T10:00:00Z",
            }
        ]
        alternate_path = self.data_directory / "with-group.json"
        alternate_path.write_text(json.dumps(payload), encoding="utf-8")
        result = FriendLibrary.from_path(alternate_path).get_groups()
        self.assertEqual(result["counts"], {"persisted": 1, "inferred": 1})
        self.assertEqual(
            result["inferredGroups"][0]["memberIDs"],
            ["person-ada", "person-bo", "person-cleo"],
        )

    def test_identical_manual_or_rejected_group_suppresses_duplicate(self) -> None:
        for status in ("manual", "rejected"):
            with self.subTest(status=status):
                payload = copy.deepcopy(self.payload)
                payload["groups"] = [
                    {
                        "id": f"group-{status}",
                        "name": "Gespeicherte Gruppe",
                        "memberIDs": [
                            "person-ada",
                            "person-bo",
                            "person-cleo",
                        ],
                        "status": status,
                        "confidence": 1.0,
                        "explanation": "Bereits gespeichert.",
                        "createdAt": "2026-05-01T10:00:00Z",
                    }
                ]
                alternate_path = self.data_directory / f"with-{status}-group.json"
                alternate_path.write_text(json.dumps(payload), encoding="utf-8")

                result = FriendLibrary.from_path(alternate_path).get_groups()

                self.assertEqual(
                    result["counts"], {"persisted": 1, "inferred": 0}
                )

    def test_media_previews_only_expose_paths_inside_data_directory(self) -> None:
        result = self.library.get_media_previews("Ada Beispiel", limit=10)
        media = {item["id"]: item for item in result["media"]}
        self.assertTrue(media["media-ada"]["available"])
        self.assertEqual(
            Path(media["media-ada"]["localPath"]),
            (self.media_directory / "ada.jpg").resolve(),
        )
        self.assertFalse(media["media-unsafe"]["available"])
        self.assertIsNone(media["media-unsafe"]["localPath"])

    def test_natural_language_queries_return_compact_grounded_answers(self) -> None:
        location = self.library.query_friend_library("Wo wohnt Ada?")
        self.assertEqual(location["matchedIntent"], "location")
        self.assertIn("Nordstadt", location["answer"])

        age = self.library.query_friend_library("Wie alt ist Ada Beispiel?")
        self.assertEqual(age["matchedIntent"], "age")
        self.assertEqual(age["matchedPerson"]["id"], "person-ada")

        style = self.library.query_friend_library("Was trägt Ada meistens?")
        self.assertEqual(style["matchedIntent"], "style")
        self.assertIn("grüne Jacke", style["answer"])

        links = self.library.query_friend_library("Wie lautet Adas Instagram-Link?")
        self.assertEqual(links["matchedIntent"], "links")
        self.assertIn("Instagram", links["answer"])
        self.assertEqual(
            links["evidence"]["links"][0]["url"],
            "https://www.instagram.com/ada.beispiel/",
        )
        self.assertEqual(
            links["evidence"]["counts"],
            {"total": 2, "confirmed": 1, "unconfirmed": 1},
        )

        overview = self.library.query_friend_library("Wer ist Ada?")
        self.assertIn("[unbestätigt]", overview["answer"])

    def test_every_query_is_read_only(self) -> None:
        before = hashlib.sha256(self.data_path.read_bytes()).hexdigest()
        self.library.search_people("")
        self.library.get_person("person-ada")
        self.library.get_relationships()
        self.library.get_groups()
        self.library.get_media_previews()
        self.library.query_friend_library("Wer ist Ada?")
        after = hashlib.sha256(self.data_path.read_bytes()).hexdigest()
        self.assertEqual(before, after)

    def test_call_tool_rejects_unknown_arguments(self) -> None:
        with self.assertRaises(FriendLibraryInputError):
            call_tool(
                self.library,
                "search_people",
                {"query": "Ada", "write": True},
            )

    def test_save_person_creates_and_partially_updates_swift_compatible_data(self) -> None:
        created = call_tool(
            self.library,
            "save_person",
            {
                "name": "Dana Beispiel",
                "aliases": ["Dani"],
                "birthday": "2001-03-04",
                "location": "Weststadt",
                "interests": ["Lesen"],
                "profileDetails": {
                    "favoriteColors": ["Blau"],
                    "favoriteFoods": ["Pasta"],
                    "custom:Lieblingswort": ["Moin"],
                },
            },
        )
        person_id = created["person"]["id"]
        uuid.UUID(person_id)
        self.assertEqual(created["action"], "created")
        self.assertEqual(created["person"]["name"], "Dana Beispiel")

        updated = call_tool(
            self.library,
            "save_person",
            {"person": person_id, "summary": "Mag ruhige Cafés.", "location": None},
        )
        self.assertEqual(updated["action"], "updated")
        self.assertEqual(updated["person"]["summary"], "Mag ruhige Cafés.")
        self.assertIsNone(updated["person"]["location"])

        details_updated = call_tool(
            self.library,
            "save_person",
            {
                "person": person_id,
                "profileDetails": {
                    "favoriteColors": ["Grün"],
                    "favoriteFoods": [],
                },
            },
        )
        self.assertEqual(
            details_updated["person"]["profileDetails"]["favoriteColors"],
            ["Grün"],
        )
        self.assertNotIn(
            "favoriteFoods", details_updated["person"]["profileDetails"]
        )
        self.assertEqual(
            details_updated["person"]["profileDetails"]["custom:Lieblingswort"],
            ["Moin"],
        )

        payload = json.loads(self.data_path.read_text(encoding="utf-8"))
        stored = next(person for person in payload["people"] if person["id"] == person_id)
        self.assertEqual(stored["birthday"], "2001-03-04T00:00:00Z")
        self.assertEqual(stored["interests"], ["Lesen"])
        self.assertEqual(stored["profileDetails"]["favoriteColors"], ["Grün"])
        self.assertNotIn("favoriteFoods", stored["profileDetails"])
        self.assertEqual(
            created["person"]["profileDetails"]["custom:Lieblingswort"],
            ["Moin"],
        )
        self.assertEqual(
            self.library.search_people("Moin")["people"][0]["id"],
            person_id,
        )
        self.assertFalse(
            any(path.name.startswith(".friends-") for path in self.data_directory.iterdir())
        )

    def test_write_rotates_previous_and_current_backup(self) -> None:
        previous_path = self.data_directory / "friends.previous.json"
        backup_path = self.data_directory / "friends.backup.json"
        original_contents = self.data_path.read_bytes()

        call_tool(
            self.library,
            "save_person",
            {"person": "person-bo", "summary": "Erste Änderung"},
        )
        first_saved_contents = self.data_path.read_bytes()

        self.assertEqual(previous_path.read_bytes(), original_contents)
        self.assertEqual(backup_path.read_bytes(), first_saved_contents)
        self.assertEqual(
            json.loads(backup_path.read_text(encoding="utf-8"))["people"][1][
                "summary"
            ],
            "Erste Änderung",
        )

        call_tool(
            self.library,
            "save_person",
            {"person": "person-bo", "summary": "Zweite Änderung"},
        )
        second_saved_contents = self.data_path.read_bytes()

        self.assertEqual(previous_path.read_bytes(), first_saved_contents)
        self.assertEqual(backup_path.read_bytes(), second_saved_contents)

    def test_failed_main_write_restores_existing_backup(self) -> None:
        previous_path = self.data_directory / "friends.previous.json"
        backup_path = self.data_directory / "friends.backup.json"
        original_contents = self.data_path.read_bytes()
        old_backup = b'{"oldBackup": true}\n'
        backup_path.write_bytes(old_backup)
        real_replace = os.replace

        def fail_main_replace(
            source: str | os.PathLike[str],
            target: str | os.PathLike[str],
        ) -> None:
            if Path(target).resolve() == self.data_path.resolve():
                raise OSError("synthetic main write failure")
            real_replace(source, target)

        with patch(
            "freundeblick_mcp.os.replace",
            side_effect=fail_main_replace,
        ):
            with self.assertRaisesRegex(OSError, "synthetic main write failure"):
                call_tool(
                    self.library,
                    "save_person",
                    {"person": "person-bo", "summary": "Darf nicht bleiben"},
                )

        self.assertEqual(self.data_path.read_bytes(), original_contents)
        self.assertEqual(previous_path.read_bytes(), original_contents)
        self.assertEqual(backup_path.read_bytes(), old_backup)
        self.assertFalse(
            any(
                path.name.endswith(".tmp")
                for path in self.data_directory.iterdir()
            )
        )

    def test_failed_main_write_removes_new_backup_if_none_existed(self) -> None:
        backup_path = self.data_directory / "friends.backup.json"
        original_contents = self.data_path.read_bytes()
        real_replace = os.replace

        def fail_main_replace(
            source: str | os.PathLike[str],
            target: str | os.PathLike[str],
        ) -> None:
            if Path(target).resolve() == self.data_path.resolve():
                raise OSError("synthetic main write failure")
            real_replace(source, target)

        with patch(
            "freundeblick_mcp.os.replace",
            side_effect=fail_main_replace,
        ):
            with self.assertRaisesRegex(OSError, "synthetic main write failure"):
                call_tool(
                    self.library,
                    "save_person",
                    {"person": "person-bo", "summary": "Darf nicht bleiben"},
                )

        self.assertEqual(self.data_path.read_bytes(), original_contents)
        self.assertFalse(backup_path.exists())

    def test_write_rejects_future_schema_without_creating_backups(self) -> None:
        future_payload = copy.deepcopy(self.payload)
        future_payload["schemaVersion"] = 2
        self.data_path.write_text(
            json.dumps(future_payload, ensure_ascii=False, sort_keys=True),
            encoding="utf-8",
        )
        self.library = FriendLibrary.from_path(self.data_path)
        original_contents = self.data_path.read_bytes()

        with self.assertRaisesRegex(
            FriendLibraryInputError,
            "Datenbankversion 2",
        ):
            call_tool(
                self.library,
                "save_person",
                {"person": "person-bo", "summary": "Nicht schreiben"},
            )

        self.assertEqual(self.data_path.read_bytes(), original_contents)
        self.assertFalse(
            (self.data_directory / "friends.previous.json").exists()
        )
        self.assertFalse(
            (self.data_directory / "friends.backup.json").exists()
        )

    def test_save_profile_link_is_safe_and_idempotent_by_url(self) -> None:
        first = call_tool(
            self.library,
            "save_profile_link",
            {
                "person": "person-bo",
                "url": "https://example.com/bo",
                "platform": "website",
                "title": "Bos Seite",
                "handle": "@bo",
            },
        )
        second = call_tool(
            self.library,
            "save_profile_link",
            {
                "person": "person-bo",
                "url": "https://example.com/bo",
                "platform": "website",
                "title": "Bos neue Seite",
                "confirmed": True,
            },
        )
        self.assertEqual(first["action"], "created")
        self.assertEqual(second["action"], "updated")
        self.assertEqual(first["link"]["id"], second["link"]["id"])
        uuid.UUID(first["link"]["id"])
        self.assertTrue(second["link"]["confirmed"])

        partial_update = call_tool(
            self.library,
            "save_profile_link",
            {
                "person": "person-bo",
                "linkID": first["link"]["id"],
                "url": "https://example.com/bo/aktuell",
            },
        )
        self.assertEqual(partial_update["action"], "updated")
        self.assertEqual(partial_update["link"]["platform"], "website")
        self.assertEqual(partial_update["link"]["kind"], "website")
        self.assertEqual(partial_update["link"]["title"], "Bos neue Seite")
        self.assertEqual(partial_update["link"]["handle"], "@bo")
        self.assertTrue(partial_update["link"]["confirmed"])

        with self.assertRaises(FriendLibraryInputError):
            call_tool(
                self.library,
                "save_profile_link",
                {"person": "person-bo", "url": "http://localhost/private"},
            )

    def test_save_relationship_upserts_both_directions(self) -> None:
        before_count = len(self.library.relationship_claims)
        result = call_tool(
            self.library,
            "save_relationship",
            {
                "fromPerson": "person-ada",
                "toPerson": "person-bo",
                "status": "confirmed",
                "source": "imported",
                "notes": "Bleibt erhalten.",
                "reciprocal": True,
            },
        )
        self.assertEqual(len(result["relationships"]), 2)
        self.assertTrue(
            all(relationship["action"] == "updated" for relationship in result["relationships"])
        )
        self.assertEqual(len(self.library.relationship_claims), before_count)
        self.assertTrue(
            all(relationship["status"] == "confirmed" for relationship in result["relationships"])
        )

        partial_update = call_tool(
            self.library,
            "save_relationship",
            {
                "fromPerson": "person-ada",
                "toPerson": "person-bo",
                "reciprocal": True,
            },
        )
        self.assertTrue(
            all(
                relationship["status"] == "confirmed"
                and relationship["source"] == "imported"
                and relationship["notes"] == "Bleibt erhalten."
                for relationship in partial_update["relationships"]
            )
        )

    def test_save_family_relationship_uses_inverse_role_and_is_pairwise(self) -> None:
        result = call_tool(
            self.library,
            "save_relationship",
            {
                "fromPerson": "person-ada",
                "toPerson": "person-bo",
                "kind": "family",
                "familyRole": "parent",
                "status": "confirmed",
                "source": "personStatement",
                "notes": "Direkt bestätigt.",
                "reciprocal": True,
            },
        )

        self.assertEqual(
            [relationship["familyRole"] for relationship in result["relationships"]],
            ["parent", "child"],
        )

        partial_update = call_tool(
            self.library,
            "save_relationship",
            {
                "fromPerson": "person-ada",
                "toPerson": "person-bo",
                "kind": "family",
                "reciprocal": True,
            },
        )
        self.assertEqual(
            [relationship["familyRole"] for relationship in partial_update["relationships"]],
            ["parent", "child"],
        )
        self.assertTrue(
            all(
                relationship["status"] == "confirmed"
                and relationship["source"] == "personStatement"
                and relationship["notes"] == "Direkt bestätigt."
                for relationship in partial_update["relationships"]
            )
        )

        relationships = self.library.get_relationships("person-ada")
        self.assertEqual(len(relationships["mutualFamilies"]), 1)
        self.assertEqual(relationships["counts"]["mutualFamilies"], 1)
        self.assertFalse(
            any(
                set(item["personIDs"]) == {"person-bo", "person-cleo"}
                for item in relationships["mutualFamilies"]
            )
        )

    def test_save_observation_defaults_to_unverified_and_supports_update(self) -> None:
        created = call_tool(
            self.library,
            "save_observation",
            {
                "person": "person-bo",
                "category": "interest",
                "value": "mag Brettspiele",
            },
        )
        observation_id = created["observation"]["id"]
        uuid.UUID(observation_id)
        self.assertEqual(created["observation"]["status"], "unverified")
        self.assertEqual(created["observation"]["confidence"], 0.5)

        updated = call_tool(
            self.library,
            "save_observation",
            {
                "person": "person-bo",
                "observationID": observation_id,
                "category": "interest",
                "value": "mag kooperative Brettspiele",
                "status": "confirmed",
                "confidence": 1,
                "source": "imported",
                "evidenceMediaIDs": ["media-ada"],
            },
        )
        self.assertEqual(updated["action"], "updated")
        self.assertEqual(updated["observation"]["status"], "confirmed")
        self.assertEqual(updated["observation"]["value"], "mag kooperative Brettspiele")

        partial_update = call_tool(
            self.library,
            "save_observation",
            {
                "person": "person-bo",
                "observationID": observation_id,
                "category": "interest",
                "value": "mag komplexe kooperative Brettspiele",
            },
        )
        self.assertEqual(partial_update["observation"]["status"], "confirmed")
        self.assertEqual(partial_update["observation"]["confidence"], 1.0)
        self.assertEqual(partial_update["observation"]["source"], "imported")
        self.assertEqual(
            partial_update["observation"]["evidenceMediaIDs"], ["media-ada"]
        )


class MCPProtocolTestCase(LibraryTestCase):
    def setUp(self) -> None:
        super().setUp()
        self.server = MCPServer(self.library)

    def test_initialize_negotiates_current_protocol(self) -> None:
        response = self.server.handle(
            {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "protocolVersion": "2099-01-01",
                    "capabilities": {},
                    "clientInfo": {"name": "test", "version": "1"},
                },
            }
        )
        self.assertEqual(response["result"]["protocolVersion"], PROTOCOL_VERSION)
        self.assertEqual(
            response["result"]["capabilities"], {"tools": {"listChanged": False}}
        )

    def test_tools_list_exposes_read_and_write_tools_with_correct_annotations(self) -> None:
        response = self.server.handle(
            {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}}
        )
        tools = response["result"]["tools"]
        self.assertEqual(
            [tool["name"] for tool in tools],
            [
                "search_people",
                "get_person",
                "get_relationships",
                "get_groups",
                "get_media_previews",
                "query_friend_library",
                "save_person",
                "save_profile_link",
                "save_relationship",
                "save_observation",
            ],
        )
        self.assertEqual(tools, TOOLS)
        self.assertTrue(
            all(tool["annotations"]["readOnlyHint"] for tool in tools[:6])
        )
        self.assertTrue(
            all(not tool["annotations"]["readOnlyHint"] for tool in tools[6:])
        )
        self.assertTrue(
            all(not tool["annotations"]["destructiveHint"] for tool in tools)
        )

    def test_tools_call_returns_text_and_matching_structured_content(self) -> None:
        response = self.server.handle(
            {
                "jsonrpc": "2.0",
                "id": 3,
                "method": "tools/call",
                "params": {
                    "name": "search_people",
                    "arguments": {"query": "Ada"},
                },
            }
        )
        result = response["result"]
        self.assertFalse(result["isError"])
        self.assertEqual(
            json.loads(result["content"][0]["text"]),
            result["structuredContent"],
        )

    def test_tool_input_errors_are_mcp_tool_errors(self) -> None:
        response = self.server.handle(
            {
                "jsonrpc": "2.0",
                "id": 4,
                "method": "tools/call",
                "params": {
                    "name": "get_person",
                    "arguments": {"person": "Nicht Vorhanden"},
                },
            }
        )
        self.assertTrue(response["result"]["isError"])
        self.assertIn("Keine Person", response["result"]["content"][0]["text"])

    def test_unknown_tool_is_protocol_error(self) -> None:
        response = self.server.handle(
            {
                "jsonrpc": "2.0",
                "id": 5,
                "method": "tools/call",
                "params": {"name": "delete_everything", "arguments": {}},
            }
        )
        self.assertEqual(response["error"]["code"], -32602)

    def test_notifications_do_not_receive_responses(self) -> None:
        response = self.server.handle(
            {
                "jsonrpc": "2.0",
                "method": "notifications/initialized",
                "params": {},
            }
        )
        self.assertIsNone(response)

    def test_stdio_server_uses_one_json_message_per_line(self) -> None:
        requests = [
            {
                "jsonrpc": "2.0",
                "id": "init",
                "method": "initialize",
                "params": {
                    "protocolVersion": PROTOCOL_VERSION,
                    "capabilities": {},
                    "clientInfo": {"name": "test", "version": "1"},
                },
            },
            {
                "jsonrpc": "2.0",
                "method": "notifications/initialized",
                "params": {},
            },
            {
                "jsonrpc": "2.0",
                "id": "list",
                "method": "tools/list",
                "params": {},
            },
            {
                "jsonrpc": "2.0",
                "id": "call",
                "method": "tools/call",
                "params": {
                    "name": "query_friend_library",
                    "arguments": {"question": "Wo wohnt Ada?"},
                },
            },
        ]
        standard_input = "".join(
            json.dumps(request, ensure_ascii=False) + "\n" for request in requests
        )
        environment = dict(os.environ)
        environment["PYTHONPYCACHEPREFIX"] = str(
            Path(self.temporary_directory.name) / "pycache"
        )
        completed = subprocess.run(
            [
                sys.executable,
                str(TOOLS_DIRECTORY / "freundeblick_mcp.py"),
                "--data",
                str(self.data_path),
            ],
            input=standard_input,
            text=True,
            capture_output=True,
            check=False,
            cwd=WORKSPACE,
            env=environment,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertEqual(completed.stderr, "")
        lines = completed.stdout.splitlines()
        self.assertEqual(len(lines), 3)
        messages = [json.loads(line) for line in lines]
        self.assertEqual([message["id"] for message in messages], ["init", "list", "call"])
        self.assertIn(
            "Nordstadt",
            messages[2]["result"]["structuredContent"]["answer"],
        )

    def test_cli_uses_the_same_read_only_tool_layer(self) -> None:
        environment = dict(os.environ)
        environment["PYTHONPYCACHEPREFIX"] = str(
            Path(self.temporary_directory.name) / "pycache-cli"
        )
        completed = subprocess.run(
            [
                sys.executable,
                str(TOOLS_DIRECTORY / "freundeblick_cli.py"),
                "--data",
                str(self.data_path),
                "--compact",
                "ask",
                "Wie lautet Adas Instagram-Link?",
            ],
            text=True,
            capture_output=True,
            check=False,
            cwd=WORKSPACE,
            env=environment,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        result = json.loads(completed.stdout)
        self.assertEqual(result["matchedPerson"]["id"], "person-ada")
        self.assertEqual(result["matchedIntent"], "links")
        self.assertEqual(
            result["evidence"]["links"][0]["handle"],
            "@ada.beispiel",
        )


if __name__ == "__main__":
    unittest.main()
