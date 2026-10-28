from __future__ import annotations

import json
import os
import tempfile
import uuid
from copy import deepcopy
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


class NoteStore:
    """Small JSON-backed note store with atomic writes."""

    def __init__(self, path: Path) -> None:
        self.path = path
        self._notes: list[dict[str, Any]] = []
        self.load()

    def load(self) -> None:
        if not self.path.exists():
            self._notes = []
            return

        with self.path.open("r", encoding="utf-8") as file:
            payload = json.load(file)

        if not isinstance(payload, list):
            raise ValueError("备忘录数据格式无效：根节点应为列表。")

        self._notes = [self._normalise(note) for note in payload if isinstance(note, dict)]

    @staticmethod
    def _normalise(note: dict[str, Any]) -> dict[str, Any]:
        created_at = str(note.get("created_at") or _now())
        return {
            "id": str(note.get("id") or uuid.uuid4()),
            "title": str(note.get("title") or ""),
            "content": str(note.get("content") or ""),
            "pinned": bool(note.get("pinned", False)),
            "created_at": created_at,
            "updated_at": str(note.get("updated_at") or created_at),
        }

    def all(self) -> list[dict[str, Any]]:
        notes = sorted(
            self._notes,
            key=lambda note: (bool(note["pinned"]), str(note["updated_at"])),
            reverse=True,
        )
        return deepcopy(notes)

    def get(self, note_id: str) -> dict[str, Any] | None:
        for note in self._notes:
            if note["id"] == note_id:
                return deepcopy(note)
        return None

    def search(self, query: str) -> list[dict[str, Any]]:
        needle = query.strip().casefold()
        if not needle:
            return self.all()
        return [
            note
            for note in self.all()
            if needle in note["title"].casefold() or needle in note["content"].casefold()
        ]

    def create(self, title: str = "新备忘录", content: str = "") -> dict[str, Any]:
        timestamp = _now()
        note = {
            "id": str(uuid.uuid4()),
            "title": title,
            "content": content,
            "pinned": False,
            "created_at": timestamp,
            "updated_at": timestamp,
        }
        self._notes.append(note)
        self.save()
        return deepcopy(note)

    def update(self, note_id: str, **changes: Any) -> dict[str, Any] | None:
        allowed = {"title", "content", "pinned"}
        for note in self._notes:
            if note["id"] != note_id:
                continue
            changed = False
            for key, value in changes.items():
                if key in allowed and note[key] != value:
                    note[key] = value
                    changed = True
            if changed:
                note["updated_at"] = _now()
                self.save()
            return deepcopy(note)
        return None

    def delete(self, note_id: str) -> bool:
        original_count = len(self._notes)
        self._notes = [note for note in self._notes if note["id"] != note_id]
        if len(self._notes) == original_count:
            return False
        self.save()
        return True

    def save(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        descriptor, temporary_name = tempfile.mkstemp(
            prefix="notes-", suffix=".tmp", dir=self.path.parent
        )
        try:
            with os.fdopen(descriptor, "w", encoding="utf-8") as file:
                json.dump(self._notes, file, ensure_ascii=False, indent=2)
                file.flush()
                os.fsync(file.fileno())
            os.replace(temporary_name, self.path)
        except Exception:
            try:
                os.unlink(temporary_name)
            except FileNotFoundError:
                pass
            raise

