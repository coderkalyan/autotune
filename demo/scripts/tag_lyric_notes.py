#!/usr/bin/env python3
"""Interactive MIDI note tagger for lyrics.json files.

Walks each word in a lyrics.json. Prints the word, collects MIDI note_on
events from a connected keyboard while the user is on that word, and commits
when the user presses Enter. Saves an updated lyrics.json with a `note` field
on each word: an int when one note was played, or a list[int] when multiple.

Usage:
    python tag_lyric_notes.py path/to/lyrics.json [--port PORT_NAME] [--retag]
"""

import argparse
import json
import sys
import threading
from pathlib import Path

import mido
import mido.backends.rtmidi  # noqa: F401


def pick_port() -> str:
    ports = mido.get_input_names()
    if not ports:
        sys.exit("No MIDI input ports found. Connect a keyboard and retry.")
    print("Available MIDI input ports:")
    for i, name in enumerate(ports):
        print(f"  [{i}] {name}")
    while True:
        sel = input("Select port index: ").strip()
        try:
            idx = int(sel)
            return ports[idx]
        except (ValueError, IndexError):
            print("Invalid index, try again.")


class NoteCollector:
    """Background MIDI listener that appends note_on numbers to a buffer."""

    def __init__(self, port_name: str):
        self._port = mido.open_input(port_name)
        self._lock = threading.Lock()
        self._notes: list[int] = []
        self._stop = threading.Event()
        self._thread = threading.Thread(
            target=self._run, daemon=True, name="midi-tag-collector"
        )
        self._thread.start()

    def _run(self) -> None:
        try:
            for msg in self._port:
                if self._stop.is_set():
                    break
                if msg.bytes() == [0xF8]:
                    continue
                if msg.type == "note_on" and getattr(msg, "velocity", 0) > 0:
                    if getattr(msg, "channel", 0) != 0:
                        continue
                    with self._lock:
                        self._notes.append(msg.note)
                    print(f"    + note {msg.note}")
        except Exception as e:
            print(f"[collector] error: {e}")

    def take(self) -> list[int]:
        with self._lock:
            notes = self._notes[:]
            self._notes.clear()
            return notes

    def reset(self) -> None:
        with self._lock:
            self._notes.clear()

    def close(self) -> None:
        self._stop.set()
        try:
            self._port.close()
        except Exception:
            pass


def atomic_save(path: Path, data) -> None:
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, indent=2, ensure_ascii=False))
    tmp.replace(path)


def flatten_words(lyrics):
    """Yield (line_idx, word_idx) for every word in the document."""
    for i, line in enumerate(lyrics):
        for j, _ in enumerate(line.get("words", [])):
            yield (i, j)


def get_word(lyrics, idx_pair):
    i, j = idx_pair
    return lyrics[i]["words"][j]


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Tag lyrics.json words with MIDI notes"
    )
    parser.add_argument("lyrics", type=Path, help="Path to lyrics.json")
    parser.add_argument("--port", help="MIDI input port name (otherwise prompted)")
    parser.add_argument(
        "--retag",
        action="store_true",
        help="Revisit words that already have a `note` field (default: skip them)",
    )
    args = parser.parse_args()

    if not args.lyrics.exists():
        sys.exit(f"File not found: {args.lyrics}")

    data = json.loads(args.lyrics.read_text())
    if not isinstance(data, list):
        sys.exit("Expected lyrics.json to be a list of lines")

    port_name = args.port or pick_port()
    print(f"Using MIDI port: {port_name}\n")
    collector = NoteCollector(port_name)

    word_indices = list(flatten_words(data))
    total = len(word_indices)
    if total == 0:
        sys.exit("No words found in lyrics.json")

    print("Controls:")
    print("  <Enter>    — commit collected notes & advance")
    print("  u <Enter>  — undo notes collected on current word")
    print("  b <Enter>  — back to previous word (force-show even if tagged)")
    print("  s <Enter>  — skip / clear note on this word")
    print("  q <Enter>  — quit (progress already saved)")
    print()

    pos = 0
    force_show = False
    try:
        while pos < total:
            idx_pair = word_indices[pos]
            word = get_word(data, idx_pair)
            existing = word.get("note")

            if existing is not None and not args.retag and not force_show:
                pos += 1
                continue
            force_show = False

            collector.reset()
            i, j = idx_pair
            existing_str = f"  (current: {existing})" if existing is not None else ""
            print(
                f"[{pos + 1}/{total}] line {i} word {j}: "
                f"{word.get('text', '')!r}{existing_str}"
            )
            cmd = input("  > ").strip().lower()

            if cmd == "q":
                break
            if cmd == "u":
                collector.reset()
                continue
            if cmd == "b":
                pos = max(0, pos - 1)
                force_show = True
                continue
            if cmd == "s":
                word.pop("note", None)
                atomic_save(args.lyrics, data)
                pos += 1
                continue
            if cmd != "":
                print(f"  unknown command {cmd!r}; staying on this word")
                continue

            notes = collector.take()
            if not notes:
                print("  no notes collected — play a note or use s to skip")
                continue

            word["note"] = notes[0] if len(notes) == 1 else notes
            atomic_save(args.lyrics, data)
            print(f"  -> note = {word['note']}")
            pos += 1
    finally:
        collector.close()
        atomic_save(args.lyrics, data)
        print(f"\nSaved → {args.lyrics}")


if __name__ == "__main__":
    main()
