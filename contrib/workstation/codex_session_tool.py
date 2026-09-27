#!/usr/bin/env python3
"""Fast, name-aware Codex session picker and safe cwd migration helper."""

from __future__ import annotations

import argparse
import curses
import datetime as dt
import json
import locale
import os
import sqlite3
import sys
import tempfile
from dataclasses import dataclass, replace
from pathlib import Path
from typing import Iterable, Sequence


@dataclass(frozen=True)
class Session:
    session_id: str
    rollout_path: str
    cwd: str
    source: str
    name: str
    preview: str
    title: str
    first_user_message: str
    is_pinned: bool
    recency_ms: int

    @property
    def label(self) -> str:
        return clean_text(
            self.name
            or self.preview
            or self.title
            or self.first_user_message
            or self.session_id
        )

    @property
    def searchable_text(self) -> str:
        return " ".join(
            (
                self.name,
                self.preview,
                self.title,
                self.first_user_message,
                self.cwd,
                self.source,
                self.session_id,
            )
        ).casefold()


def clean_text(value: str) -> str:
    return " ".join((value or "").replace("\x00", " ").split())


def parse_index_timestamp(value: object) -> float:
    if not isinstance(value, str) or not value:
        return 0.0
    try:
        return dt.datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
    except (OSError, OverflowError, ValueError):
        return 0.0


def load_session_names(
    index_paths: Sequence[Path], wanted_ids: set[str]
) -> dict[str, str]:
    """Load the newest /rename value for selected sessions.

    Current Codex releases append names to session_index.jsonl. Older state
    databases may leave threads.name blank, especially when CODEX_HOME points
    at an account profile while the picker uses a shared SQLite index.
    """

    newest: dict[str, tuple[float, int, str]] = {}
    sequence = 0
    seen_paths: set[Path] = set()
    for raw_path in index_paths:
        path = raw_path.expanduser().resolve(strict=False)
        if path in seen_paths or not path.is_file():
            continue
        seen_paths.add(path)
        try:
            with path.open("r", encoding="utf-8", errors="replace") as handle:
                for line in handle:
                    sequence += 1
                    try:
                        item = json.loads(line)
                    except (json.JSONDecodeError, TypeError):
                        # A concurrently appended or legacy malformed final
                        # record must not break the resume picker.
                        continue
                    session_id = item.get("id")
                    if session_id not in wanted_ids:
                        continue
                    name = item.get("thread_name")
                    if not isinstance(name, str):
                        continue
                    candidate = (
                        parse_index_timestamp(item.get("updated_at")),
                        sequence,
                        clean_text(name),
                    )
                    previous = newest.get(session_id)
                    if previous is None or candidate[:2] >= previous[:2]:
                        newest[session_id] = candidate
        except OSError:
            continue
    return {session_id: value[2] for session_id, value in newest.items()}


def open_database(path: Path, *, read_only: bool) -> sqlite3.Connection:
    if read_only:
        uri = f"file:{path.resolve()}?mode=ro"
        connection = sqlite3.connect(uri, uri=True, timeout=5)
        connection.execute("PRAGMA query_only=ON")
    else:
        connection = sqlite3.connect(path, timeout=10)
        connection.execute("PRAGMA busy_timeout=10000")
    connection.row_factory = sqlite3.Row
    return connection


def query_sessions(
    db_path: Path,
    *,
    scope: str,
    cwd: str,
    query: str,
    include_non_interactive: bool,
    limit: int,
    session_indexes: Sequence[Path] = (),
) -> list[Session]:
    conditions = [
        "archived = 0",
        "("
        "trim(COALESCE(name, '')) <> '' OR "
        "trim(COALESCE(preview, '')) <> '' OR "
        "trim(COALESCE(title, '')) <> '' OR "
        "trim(COALESCE(first_user_message, '')) <> ''"
        ")",
    ]
    parameters: list[object] = []

    if not include_non_interactive:
        conditions.append("source IN ('cli', 'vscode')")

    if scope == "exact":
        conditions.append("cwd = ?")
        parameters.append(cwd)
    elif scope == "partial":
        conditions.append("instr(lower(cwd), lower(?)) > 0")
        parameters.append(query)
    elif scope != "all":
        raise ValueError(f"unknown scope: {scope}")

    parameters.append(max(1, min(limit, 1000)))

    # The state database on long-lived installations can be many gigabytes.
    # SQLite otherwise tends to choose idx_threads_archived and scan almost the
    # entire table for --all. Interactive sessions are sparse, so its source
    # index is dramatically faster. For all-source views, the recency indexes
    # let LIMIT stop the scan early.
    with open_database(db_path, read_only=True) as connection:
        available_indexes = {
            row[1] for row in connection.execute("PRAGMA index_list(threads)").fetchall()
        }
        index_hint = ""
        if not include_non_interactive and "idx_threads_source" in available_indexes:
            index_hint = " INDEXED BY idx_threads_source"
        elif scope == "exact" and "idx_threads_archived_cwd_recency_at_ms" in available_indexes:
            index_hint = " INDEXED BY idx_threads_archived_cwd_recency_at_ms"
        elif "idx_threads_recency_at_ms" in available_indexes:
            index_hint = " INDEXED BY idx_threads_recency_at_ms"

        if include_non_interactive:
            order_by = "recency_at_ms DESC, id DESC"
        else:
            order_by = "is_pinned DESC, recency_at_ms DESC, id DESC"

        sql = f"""
        SELECT id,
               rollout_path,
               cwd,
               substr(COALESCE(source, ''), 1, 40) AS source,
               substr(COALESCE(name, ''), 1, 300) AS name,
               substr(COALESCE(preview, ''), 1, 500) AS preview,
               substr(COALESCE(title, ''), 1, 500) AS title,
               substr(COALESCE(first_user_message, ''), 1, 500) AS first_user_message,
               COALESCE(is_pinned, 0) AS is_pinned,
               COALESCE(NULLIF(recency_at_ms, 0),
                        NULLIF(updated_at_ms, 0),
                        updated_at * 1000) AS recency_ms
          FROM threads{index_hint}
         WHERE {' AND '.join(conditions)}
         ORDER BY {order_by}
         LIMIT ?
        """
        rows = connection.execute(sql, parameters).fetchall()

    sessions = [
        Session(
            session_id=row["id"],
            rollout_path=row["rollout_path"],
            cwd=row["cwd"],
            source=row["source"],
            name=row["name"],
            preview=row["preview"],
            title=row["title"],
            first_user_message=row["first_user_message"],
            is_pinned=bool(row["is_pinned"]),
            recency_ms=int(row["recency_ms"] or 0),
        )
        for row in rows
    ]
    index_paths = [db_path.parent / "session_index.jsonl", *session_indexes]
    indexed_names = load_session_names(
        index_paths, {session.session_id for session in sessions}
    )
    return [
        replace(session, name=indexed_names[session.session_id])
        if session.session_id in indexed_names
        else session
        for session in sessions
    ]


def format_time(milliseconds: int) -> str:
    try:
        return dt.datetime.fromtimestamp(milliseconds / 1000).strftime("%Y-%m-%d %H:%M")
    except (OSError, OverflowError, ValueError):
        return "unknown time"


def scope_label(scope: str, cwd: str, query: str) -> str:
    if scope == "all":
        return "all recent sessions"
    if scope == "partial":
        return f"partial cwd: {query}"
    return f"exact cwd: {cwd}"


def row_text(session: Session, *, show_cwd: bool) -> str:
    pin = "★" if session.is_pinned else " "
    name_mark = "Name: " if session.name else ""
    text = (
        f"{pin} {format_time(session.recency_ms)}  "
        f"{session.source or '?':7.7}  {name_mark}{session.label}"
    )
    if show_cwd:
        text += f"  —  {session.cwd}"
    return text


def filtered_sessions(sessions: Sequence[Session], query: str) -> list[Session]:
    words = [part.casefold() for part in query.split() if part]
    if not words:
        return list(sessions)
    return [
        session
        for session in sessions
        if all(word in session.searchable_text for word in words)
    ]


def safe_add(stdscr: "curses._CursesWindow", y: int, x: int, text: str, width: int, attr: int = 0) -> None:
    if y < 0 or x < 0 or width <= 0:
        return
    try:
        stdscr.addnstr(y, x, text, width, attr)
    except curses.error:
        pass


def curses_picker(sessions: Sequence[Session], label: str, *, show_cwd: bool) -> Session | None:
    def run(stdscr: "curses._CursesWindow") -> Session | None:
        try:
            curses.curs_set(0)
        except curses.error:
            pass
        stdscr.keypad(True)
        selected = 0
        offset = 0
        search = ""
        searching = False

        while True:
            matches = filtered_sessions(sessions, search)
            if matches:
                selected = min(selected, len(matches) - 1)
            else:
                selected = 0

            height, width = stdscr.getmaxyx()
            list_height = max(1, height - 4)
            if selected < offset:
                offset = selected
            if selected >= offset + list_height:
                offset = selected - list_height + 1
            offset = max(0, min(offset, max(0, len(matches) - list_height)))

            stdscr.erase()
            safe_add(stdscr, 0, 0, f"Codex sessions — {label}", width - 1, curses.A_BOLD)
            help_text = "↑/↓ or j/k move  Enter resume  / filter  Home/End  PgUp/PgDn  q/Esc cancel"
            safe_add(stdscr, 1, 0, help_text, width - 1, curses.A_DIM)
            search_text = f"Filter: {search}" + ("_" if searching else "")
            safe_add(stdscr, 2, 0, search_text, width - 1, curses.A_BOLD if searching else 0)

            if not matches:
                safe_add(stdscr, 3, 0, "No matching sessions.", width - 1, curses.A_BOLD)
            else:
                for screen_row, session in enumerate(matches[offset : offset + list_height], start=3):
                    absolute_index = offset + screen_row - 3
                    marker = "▶ " if absolute_index == selected else "  "
                    attr = curses.A_REVERSE | curses.A_BOLD if absolute_index == selected else 0
                    safe_add(stdscr, screen_row, 0, marker + row_text(session, show_cwd=show_cwd), width - 1, attr)

            footer = f"{len(matches)}/{len(sessions)} sessions"
            if matches:
                footer += f"  •  selected {selected + 1}"
            safe_add(stdscr, height - 1, 0, footer, width - 1, curses.A_DIM)
            stdscr.refresh()

            key = stdscr.get_wch()
            if searching:
                if key in ("\n", "\r", curses.KEY_ENTER):
                    if matches:
                        return matches[selected]
                elif key == "\x1b":
                    searching = False
                    if not search:
                        continue
                elif key in ("\b", "\x7f", curses.KEY_BACKSPACE):
                    search = search[:-1]
                    selected = 0
                    offset = 0
                elif isinstance(key, str) and key.isprintable():
                    search += key
                    selected = 0
                    offset = 0
                continue

            if key in ("\n", "\r", curses.KEY_ENTER):
                if matches:
                    return matches[selected]
            elif key in ("q", "Q", "\x1b"):
                return None
            elif key in (curses.KEY_DOWN, "j", "J") and matches:
                selected = min(len(matches) - 1, selected + 1)
            elif key in (curses.KEY_UP, "k", "K") and matches:
                selected = max(0, selected - 1)
            elif key == curses.KEY_NPAGE and matches:
                selected = min(len(matches) - 1, selected + list_height)
            elif key == curses.KEY_PPAGE and matches:
                selected = max(0, selected - list_height)
            elif key == curses.KEY_HOME and matches:
                selected = 0
            elif key == curses.KEY_END and matches:
                selected = len(matches) - 1
            elif key == "/":
                searching = True

    return curses.wrapper(run)


def numbered_picker(sessions: Sequence[Session], label: str, *, show_cwd: bool) -> Session | None:
    print(f"Codex sessions ({label}):", file=sys.stderr)
    for index, session in enumerate(sessions, start=1):
        print(f"{index:3}. {row_text(session, show_cwd=show_cwd)}", file=sys.stderr)
    try:
        choice = input(f"Resume which session? [1-{len(sessions)}, q] ")
    except (EOFError, KeyboardInterrupt):
        return None
    if choice.casefold() == "q" or not choice:
        return None
    try:
        return sessions[int(choice) - 1]
    except (ValueError, IndexError):
        print("Invalid selection.", file=sys.stderr)
        return None


def write_selection(path: Path, session: Session) -> None:
    path.write_bytes(
        session.session_id.encode("utf-8")
        + b"\x00"
        + session.cwd.encode("utf-8")
        + b"\x00"
        + session.rollout_path.encode("utf-8")
        + b"\x00"
    )


def run_pick(args: argparse.Namespace) -> int:
    sessions = query_sessions(
        Path(args.db),
        scope=args.scope,
        cwd=args.cwd,
        query=args.query,
        include_non_interactive=args.include_non_interactive,
        limit=args.limit,
        session_indexes=[Path(value) for value in args.session_index],
    )
    label = scope_label(args.scope, args.cwd, args.query)
    if not sessions:
        print(f"No Codex sessions found for {label}.", file=sys.stderr)
        if args.scope == "exact":
            print("Try: codexr --all  or  codexr --non-strict <path-part>", file=sys.stderr)
        return 1

    if args.select_index is not None:
        try:
            selected = sessions[args.select_index]
        except IndexError:
            print("Selection index is outside the result set.", file=sys.stderr)
            return 2
    elif sys.stdin.isatty() and sys.stdout.isatty() and os.environ.get("TERM", "") != "dumb":
        try:
            selected = curses_picker(sessions, label, show_cwd=args.scope != "exact")
        except curses.error:
            selected = numbered_picker(sessions, label, show_cwd=args.scope != "exact")
    else:
        selected = numbered_picker(sessions, label, show_cwd=args.scope != "exact")

    if selected is None:
        return 130
    write_selection(Path(args.output), selected)
    return 0


def session_to_dict(session: Session) -> dict[str, object]:
    return {
        "id": session.session_id,
        "rollout_path": session.rollout_path,
        "cwd": session.cwd,
        "source": session.source,
        "name": session.name,
        "label": session.label,
        "is_pinned": session.is_pinned,
        "recency_ms": session.recency_ms,
    }


def run_list(args: argparse.Namespace) -> int:
    sessions = query_sessions(
        Path(args.db),
        scope=args.scope,
        cwd=args.cwd,
        query=args.query,
        include_non_interactive=args.include_non_interactive,
        limit=args.limit,
        session_indexes=[Path(value) for value in args.session_index],
    )
    json.dump([session_to_dict(session) for session in sessions], sys.stdout, ensure_ascii=False, indent=2)
    print()
    return 0


def escape_like(value: str) -> str:
    return value.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")


def normalize_path(value: str) -> str:
    return os.path.abspath(os.path.expanduser(value)).rstrip(os.sep) or os.sep


def atomic_json(path: Path, payload: object) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary_name, 0o600)
        os.replace(temporary_name, path)
    finally:
        if os.path.exists(temporary_name):
            os.unlink(temporary_name)


def write_move_result(path: Path, values: Iterable[str]) -> None:
    path.write_bytes(b"".join(value.encode("utf-8") + b"\x00" for value in values))


def run_move(args: argparse.Namespace) -> int:
    db_path = Path(args.db).resolve()
    old_path = normalize_path(args.old)
    new_path = normalize_path(args.new)
    if old_path == os.sep:
        print("codexmv refuses to migrate the filesystem root.", file=sys.stderr)
        return 2
    if old_path == new_path:
        print("codexmv: old and new paths are identical; nothing changed.", file=sys.stderr)
        return 2

    descendant_pattern = escape_like(old_path + os.sep) + "%"
    with open_database(db_path, read_only=False) as connection:
        try:
            # Hold the write reservation from discovery through update so a
            # concurrent Codex process cannot change a selected cwd between
            # the rollback journal and the transaction.
            connection.execute("BEGIN IMMEDIATE")
            rows = connection.execute(
                """
                SELECT id, cwd,
                       COALESCE(NULLIF(recency_at_ms, 0),
                                NULLIF(updated_at_ms, 0),
                                updated_at * 1000) AS recency_ms
                  FROM threads
                 WHERE cwd = ? OR cwd LIKE ? ESCAPE '\\'
                 ORDER BY recency_ms DESC, id DESC
                """,
                (old_path, descendant_pattern),
            ).fetchall()
            if not rows:
                connection.rollback()
                print(
                    f"codexmv: no sessions found under old path: {old_path}",
                    file=sys.stderr,
                )
                return 3

            changes: list[dict[str, str]] = []
            for row in rows:
                old_cwd = row["cwd"]
                suffix = "" if old_cwd == old_path else old_cwd[len(old_path) :]
                changes.append(
                    {
                        "id": row["id"],
                        "old_cwd": old_cwd,
                        "new_cwd": new_path + suffix,
                    }
                )

            stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
            journal_path = db_path.parent / "backups" / "codexmv" / f"move-{stamp}.json"
            atomic_json(
                journal_path,
                {
                    "created_at": dt.datetime.now(dt.timezone.utc).isoformat(),
                    "database": str(db_path),
                    "old_root": old_path,
                    "new_root": new_path,
                    "changes": changes,
                },
            )

            changes_before = connection.total_changes
            connection.executemany(
                "UPDATE threads SET cwd = ? WHERE id = ? AND cwd = ?",
                [(item["new_cwd"], item["id"], item["old_cwd"]) for item in changes],
            )
            changed_rows = connection.total_changes - changes_before
            if changed_rows != len(changes):
                raise sqlite3.IntegrityError(
                    f"expected to migrate {len(changes)} rows, changed {changed_rows}"
                )
            connection.commit()
        except Exception:
            connection.rollback()
            raise

    latest_id = rows[0]["id"]
    print(f"codexmv: migrated {len(changes)} session(s)")
    print(f"  old: {old_path}")
    print(f"  new: {new_path}")
    print(f"  rollback journal: {journal_path}")
    write_move_result(
        Path(args.output),
        (str(len(changes)), latest_id, new_path, str(journal_path)),
    )
    return 0


def add_query_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--db", required=True)
    parser.add_argument("--scope", choices=("exact", "all", "partial"), default="exact")
    parser.add_argument("--cwd", default=os.getcwd())
    parser.add_argument("--query", default="")
    parser.add_argument("--include-non-interactive", action="store_true")
    parser.add_argument("--limit", type=int, default=500)
    parser.add_argument(
        "--session-index",
        action="append",
        default=[],
        help="additional Codex session_index.jsonl rename source (repeatable)",
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    pick_parser = subparsers.add_parser("pick", help="interactively select a session")
    add_query_arguments(pick_parser)
    pick_parser.add_argument("--output", required=True)
    pick_parser.add_argument("--select-index", type=int, help=argparse.SUPPRESS)
    pick_parser.set_defaults(handler=run_pick)

    list_parser = subparsers.add_parser("list", help="emit matching sessions as JSON")
    add_query_arguments(list_parser)
    list_parser.set_defaults(handler=run_list)

    move_parser = subparsers.add_parser("move", help="rewrite stored cwd prefixes")
    move_parser.add_argument("--db", required=True)
    move_parser.add_argument("--old", required=True)
    move_parser.add_argument("--new", required=True)
    move_parser.add_argument("--output", required=True)
    move_parser.set_defaults(handler=run_move)
    return parser


def main() -> int:
    locale.setlocale(locale.LC_ALL, "")
    parser = build_parser()
    args = parser.parse_args()
    try:
        return int(args.handler(args))
    except (OSError, sqlite3.Error) as error:
        print(f"Codex session tool error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
