from __future__ import annotations

import tkinter as tk
from datetime import datetime
from pathlib import Path
from tkinter import messagebox, ttk

from desktop_memo.storage import NoteStore


BG = "#f4f1ea"
PANEL = "#fffdf8"
INK = "#292720"
MUTED = "#7b7669"
ACCENT = "#d97745"
ACCENT_ACTIVE = "#c76435"
SIDEBAR = "#e9e3d8"
SELECTED = "#f7cfb8"


class MemoApp(tk.Tk):
    def __init__(self, data_path: Path) -> None:
        super().__init__()
        self.title("桌面备忘录")
        self.geometry("980x640")
        self.minsize(760, 500)
        self.configure(bg=BG)

        self.store = NoteStore(data_path)
        self.current_id: str | None = None
        self.visible_note_ids: list[str] = []
        self.pending_save: str | None = None
        self.loading_note = False

        self.search_var = tk.StringVar()
        self.title_var = tk.StringVar()
        self.pin_var = tk.BooleanVar()
        self.status_var = tk.StringVar(value="就绪")

        self._configure_styles()
        self._build_ui()
        self._bind_shortcuts()

        self.search_var.trace_add("write", lambda *_: self.refresh_list())
        self.title_var.trace_add("write", lambda *_: self.schedule_save())

        self.refresh_list()
        if self.visible_note_ids:
            self.select_note(self.visible_note_ids[0])
        else:
            self.new_note()

        self.protocol("WM_DELETE_WINDOW", self.close_app)

    def _configure_styles(self) -> None:
        style = ttk.Style(self)
        style.theme_use("clam")
        style.configure("Memo.Treeview", background=SIDEBAR, fieldbackground=SIDEBAR,
                        foreground=INK, rowheight=54, borderwidth=0, font=("Microsoft YaHei UI", 10))
        style.map("Memo.Treeview", background=[("selected", SELECTED)],
                  foreground=[("selected", INK)])
        style.configure("Memo.Treeview.Heading", background=SIDEBAR, foreground=MUTED,
                        relief="flat", font=("Microsoft YaHei UI", 9, "bold"))
        style.configure("TSeparator", background="#d8d1c5")

    def _build_ui(self) -> None:
        root = tk.Frame(self, bg=BG)
        root.pack(fill="both", expand=True)

        sidebar = tk.Frame(root, bg=SIDEBAR, width=330)
        sidebar.pack(side="left", fill="y")
        sidebar.pack_propagate(False)

        header = tk.Frame(sidebar, bg=SIDEBAR)
        header.pack(fill="x", padx=22, pady=(22, 14))
        tk.Label(header, text="我的备忘录", bg=SIDEBAR, fg=INK,
                 font=("Microsoft YaHei UI", 18, "bold")).pack(side="left")
        tk.Button(header, text="＋", command=self.new_note, bg=ACCENT, fg="white",
                  activebackground=ACCENT_ACTIVE, activeforeground="white", bd=0,
                  font=("Microsoft YaHei UI", 16, "bold"), width=3,
                  cursor="hand2").pack(side="right")

        search_frame = tk.Frame(sidebar, bg=PANEL, highlightthickness=1,
                                highlightbackground="#d8d1c5")
        search_frame.pack(fill="x", padx=22, pady=(0, 14))
        tk.Label(search_frame, text="⌕", bg=PANEL, fg=MUTED,
                 font=("Segoe UI Symbol", 16)).pack(side="left", padx=(10, 2))
        search = tk.Entry(search_frame, textvariable=self.search_var, bg=PANEL, fg=INK,
                          insertbackground=INK, relief="flat", bd=0,
                          font=("Microsoft YaHei UI", 10))
        search.pack(side="left", fill="x", expand=True, padx=(0, 10), pady=9)

        self.tree = ttk.Treeview(sidebar, style="Memo.Treeview", show="headings",
                                 columns=("title", "updated"), selectmode="browse")
        self.tree.heading("title", text="标题")
        self.tree.heading("updated", text="更新")
        self.tree.column("title", width=220, minwidth=140, anchor="w")
        self.tree.column("updated", width=76, minwidth=65, anchor="center")
        self.tree.pack(fill="both", expand=True, padx=(14, 4), pady=(0, 14))
        self.tree.bind("<<TreeviewSelect>>", self.on_tree_select)

        editor = tk.Frame(root, bg=PANEL)
        editor.pack(side="left", fill="both", expand=True)

        toolbar = tk.Frame(editor, bg=PANEL)
        toolbar.pack(fill="x", padx=36, pady=(28, 8))
        self.pin_button = tk.Checkbutton(
            toolbar, text="置顶", variable=self.pin_var, command=self.toggle_pin,
            bg=PANEL, fg=MUTED, activebackground=PANEL, activeforeground=INK,
            selectcolor=PANEL, font=("Microsoft YaHei UI", 10), cursor="hand2"
        )
        self.pin_button.pack(side="left")
        tk.Button(toolbar, text="删除", command=self.delete_note, bg=PANEL, fg="#b94c3d",
                  activebackground="#fae8e3", activeforeground="#98382c", bd=0,
                  font=("Microsoft YaHei UI", 10), cursor="hand2",
                  padx=10, pady=5).pack(side="right")

        self.title_entry = tk.Entry(editor, textvariable=self.title_var, bg=PANEL, fg=INK,
                                    insertbackground=INK, relief="flat", bd=0,
                                    font=("Microsoft YaHei UI", 24, "bold"))
        self.title_entry.pack(fill="x", padx=42, pady=(10, 12))

        ttk.Separator(editor).pack(fill="x", padx=42)

        self.content = tk.Text(editor, bg=PANEL, fg=INK, insertbackground=INK, relief="flat",
                               bd=0, wrap="word", undo=True, padx=0, pady=0,
                               font=("Microsoft YaHei UI", 12), spacing1=3, spacing3=5)
        self.content.pack(fill="both", expand=True, padx=42, pady=(22, 12))
        self.content.bind("<<Modified>>", self.on_content_modified)

        status = tk.Label(editor, textvariable=self.status_var, bg=PANEL, fg=MUTED,
                          anchor="e", font=("Microsoft YaHei UI", 9))
        status.pack(fill="x", padx=42, pady=(0, 18))

    def _bind_shortcuts(self) -> None:
        self.bind("<Control-n>", lambda _event: self.new_note())
        self.bind("<Control-f>", self.focus_search)
        self.bind("<Control-s>", lambda _event: self.save_current())
        self.bind("<Control-Delete>", lambda _event: self.delete_note())

    def focus_search(self, _event: tk.Event | None = None) -> str:
        for widget in self.winfo_children():
            _ = widget
        self.search_var.set("")
        # The search entry is the first Entry inside the sidebar's search frame.
        self.nametowidget(self.tree.winfo_parent()).focus_set()
        self.event_generate("<Shift-Key-Tab>")
        return "break"

    @staticmethod
    def _display_title(note: dict) -> str:
        title = note["title"].strip() or "无标题"
        prefix = "★ " if note["pinned"] else ""
        return prefix + title[:34]

    @staticmethod
    def _display_time(value: str) -> str:
        try:
            stamp = datetime.fromisoformat(value)
            local = stamp.astimezone()
            today = datetime.now().astimezone().date()
            return local.strftime("%H:%M") if local.date() == today else local.strftime("%m-%d")
        except ValueError:
            return ""

    def refresh_list(self, preserve_selection: bool = True) -> None:
        selected_id = self.current_id if preserve_selection else None
        notes = self.store.search(self.search_var.get())
        self.visible_note_ids = [note["id"] for note in notes]

        for item in self.tree.get_children():
            self.tree.delete(item)
        for note in notes:
            self.tree.insert("", "end", iid=note["id"],
                             values=(self._display_title(note), self._display_time(note["updated_at"])))

        if selected_id in self.visible_note_ids:
            self.tree.selection_set(selected_id)
            self.tree.see(selected_id)
        self.status_var.set(f"共 {len(self.store.all())} 条备忘录")

    def on_tree_select(self, _event: tk.Event) -> None:
        selected = self.tree.selection()
        if selected and selected[0] != self.current_id:
            self.save_current()
            self.select_note(selected[0])

    def select_note(self, note_id: str) -> None:
        note = self.store.get(note_id)
        if note is None:
            return
        self.loading_note = True
        self.current_id = note_id
        self.title_var.set(note["title"])
        self.pin_var.set(note["pinned"])
        self.content.delete("1.0", "end")
        self.content.insert("1.0", note["content"])
        self.content.edit_modified(False)
        self.loading_note = False
        if self.tree.exists(note_id):
            self.tree.selection_set(note_id)
            self.tree.see(note_id)
        self.status_var.set("已加载")
        self.content.focus_set()

    def new_note(self) -> None:
        self.save_current()
        self.search_var.set("")
        note = self.store.create()
        self.refresh_list(preserve_selection=False)
        self.select_note(note["id"])
        self.title_entry.selection_range(0, "end")
        self.title_entry.focus_set()

    def schedule_save(self) -> None:
        if self.loading_note or self.current_id is None:
            return
        if self.pending_save:
            self.after_cancel(self.pending_save)
        self.status_var.set("正在编辑…")
        self.pending_save = self.after(600, self.save_current)

    def on_content_modified(self, _event: tk.Event) -> None:
        if self.content.edit_modified():
            self.content.edit_modified(False)
            self.schedule_save()

    def save_current(self) -> None:
        if self.pending_save:
            self.after_cancel(self.pending_save)
            self.pending_save = None
        if self.loading_note or self.current_id is None:
            return
        self.store.update(
            self.current_id,
            title=self.title_var.get(),
            content=self.content.get("1.0", "end-1c"),
            pinned=self.pin_var.get(),
        )
        self.refresh_list()
        self.status_var.set("已自动保存")

    def toggle_pin(self) -> None:
        self.save_current()

    def delete_note(self) -> None:
        if self.current_id is None:
            return
        title = self.title_var.get().strip() or "无标题"
        if not messagebox.askyesno("删除备忘录", f"确定删除“{title}”吗？\n此操作无法撤销。", parent=self):
            return
        deleting_id = self.current_id
        self.current_id = None
        self.store.delete(deleting_id)
        self.refresh_list(preserve_selection=False)
        if self.visible_note_ids:
            self.select_note(self.visible_note_ids[0])
        else:
            self.new_note()

    def close_app(self) -> None:
        self.save_current()
        self.destroy()


def run() -> None:
    project_root = Path(__file__).resolve().parent.parent
    data_path = project_root / "data" / "notes.json"
    try:
        app = MemoApp(data_path)
    except (OSError, ValueError) as error:
        root = tk.Tk()
        root.withdraw()
        messagebox.showerror("无法打开备忘录", str(error), parent=root)
        root.destroy()
        return
    app.mainloop()

