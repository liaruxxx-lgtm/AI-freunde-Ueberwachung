#!/usr/bin/env python3
"""Command-line client for the read-only FreundeBlick library tools."""

from __future__ import annotations

import argparse
import json
import sys
from typing import Any, Sequence

from freundeblick_mcp import FriendLibrary, FriendLibraryError, call_tool


def _add_common_person(parser: argparse.ArgumentParser, required: bool = False) -> None:
    if required:
        parser.add_argument("person", help="Personen-ID, Name oder Alias")
    else:
        parser.add_argument("--person", help="Optionale Personen-ID, Name oder Alias")


def build_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="FreundeBlick-Datenbank schreibgeschützt abfragen"
    )
    parser.add_argument(
        "--data",
        metavar="PATH",
        help="Pfad zu FreundeblickData/friends.json",
    )
    parser.add_argument(
        "--compact",
        action="store_true",
        help="JSON ohne Einrückung ausgeben",
    )
    commands = parser.add_subparsers(dest="command", required=True)

    search = commands.add_parser(
        "search_people",
        aliases=["search"],
        help="Profile einschließlich gespeicherter Links durchsuchen",
    )
    search.add_argument("query", help="Suchtext; eine leere Zeichenkette listet alle")
    search.add_argument("--limit", type=int, default=20)

    person = commands.add_parser(
        "get_person",
        aliases=["person"],
        help="Profil einschließlich Social-Media- und Webseitenlinks laden",
    )
    _add_common_person(person, required=True)
    person.add_argument("--as-of", dest="asOf", help="ISO-Datum JJJJ-MM-TT")
    person.add_argument("--media-limit", dest="mediaLimit", type=int, default=6)

    relationships = commands.add_parser(
        "get_relationships", aliases=["relationships"]
    )
    _add_common_person(relationships)
    relationships.add_argument(
        "--confirmed-only",
        action="store_true",
        help="Unbestätigte Beziehungsangaben ausblenden",
    )

    groups = commands.add_parser("get_groups", aliases=["groups"])
    _add_common_person(groups)
    groups.add_argument(
        "--no-inferred",
        action="store_true",
        help="Keine vorgeschlagenen Gruppen ableiten",
    )
    groups.add_argument("--min-members", dest="minMembers", type=int, default=3)

    media = commands.add_parser("get_media_previews", aliases=["media"])
    _add_common_person(media)
    media.add_argument("--kind", choices=("image", "video"))
    media.add_argument("--query", help="Tag-, Label- oder Notizfilter")
    media.add_argument("--limit", type=int, default=24)

    query = commands.add_parser(
        "query_friend_library",
        aliases=["ask"],
        help="Fragen einschließlich Fragen nach gespeicherten Links beantworten",
    )
    query.add_argument("question", help="Frage an die lokale Freundebibliothek")
    query.add_argument("--limit", type=int, default=10)

    return parser


def _tool_call_from_arguments(arguments: argparse.Namespace) -> tuple[str, dict[str, Any]]:
    command_aliases = {
        "search": "search_people",
        "person": "get_person",
        "relationships": "get_relationships",
        "groups": "get_groups",
        "media": "get_media_previews",
        "ask": "query_friend_library",
    }
    name = command_aliases.get(arguments.command, arguments.command)

    if name == "search_people":
        values = {"query": arguments.query, "limit": arguments.limit}
    elif name == "get_person":
        values = {
            "person": arguments.person,
            "asOf": arguments.asOf,
            "mediaLimit": arguments.mediaLimit,
        }
    elif name == "get_relationships":
        values = {
            "person": arguments.person,
            "includeUnconfirmed": not arguments.confirmed_only,
        }
    elif name == "get_groups":
        values = {
            "person": arguments.person,
            "includeInferred": not arguments.no_inferred,
            "minMembers": arguments.minMembers,
        }
    elif name == "get_media_previews":
        values = {
            "person": arguments.person,
            "kind": arguments.kind,
            "query": arguments.query,
            "limit": arguments.limit,
        }
    else:
        values = {"question": arguments.question, "limit": arguments.limit}

    return name, {key: value for key, value in values.items() if value is not None}


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_argument_parser()
    arguments = parser.parse_args(argv)
    try:
        library = FriendLibrary.from_path(arguments.data)
        tool_name, tool_arguments = _tool_call_from_arguments(arguments)
        result = call_tool(library, tool_name, tool_arguments)
    except FriendLibraryError as error:
        print(str(error), file=sys.stderr)
        return 2

    if arguments.compact:
        print(
            json.dumps(
                result, ensure_ascii=False, sort_keys=True, separators=(",", ":")
            )
        )
    else:
        print(json.dumps(result, ensure_ascii=False, sort_keys=True, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
