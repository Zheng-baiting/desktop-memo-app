import json
import tempfile
import unittest
from pathlib import Path

from desktop_memo.storage import NoteStore


class NoteStoreTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.path = Path(self.temporary_directory.name) / "notes.json"
        self.store = NoteStore(self.path)

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def test_create_update_and_reload(self) -> None:
        note = self.store.create("购物", "牛奶")
        self.store.update(note["id"], content="牛奶和面包", pinned=True)

        reloaded = NoteStore(self.path)
        saved = reloaded.get(note["id"])

        self.assertIsNotNone(saved)
        self.assertEqual(saved["content"], "牛奶和面包")
        self.assertTrue(saved["pinned"])

    def test_searches_title_and_content_case_insensitively(self) -> None:
        self.store.create("Project Alpha", "meeting notes")
        self.store.create("周末", "买咖啡")

        self.assertEqual(len(self.store.search("alpha")), 1)
        self.assertEqual(len(self.store.search("咖啡")), 1)

    def test_pinned_notes_are_sorted_first(self) -> None:
        first = self.store.create("普通")
        second = self.store.create("置顶")
        self.store.update(second["id"], pinned=True)

        self.assertEqual(self.store.all()[0]["id"], second["id"])
        self.assertNotEqual(first["id"], second["id"])

    def test_delete_persists(self) -> None:
        note = self.store.create("稍后删除")
        self.assertTrue(self.store.delete(note["id"]))
        self.assertIsNone(NoteStore(self.path).get(note["id"]))

    def test_rejects_invalid_root_data(self) -> None:
        self.path.write_text(json.dumps({"not": "a list"}), encoding="utf-8")
        with self.assertRaises(ValueError):
            NoteStore(self.path)


if __name__ == "__main__":
    unittest.main()

