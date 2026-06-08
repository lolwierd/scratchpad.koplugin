# scratchpad.koplugin

A quick scratchpad for jotting and re-reading notes while you read, for [KOReader](https://github.com/koreader/koreader).

Each book gets its own pad (keyed by a stable book id, so it survives renames), plus there's one shared global pad. Notes are plain text files on the device — nothing proprietary, easy to back up or sync.

## Features

- **Per-book notes** — every book gets its own scratchpad, keyed by the book's partial MD5 (survives file renames/moves).
- **Global pad** — one shared pad across all books.
- **Full-screen editor** with Save / Reset / Close, save-on-close, and pannable scrolling.
- **Bindable** — both actions can be assigned to gestures or profiles.
- **Plain text storage** — notes live in `koreader/scratchpads/*.txt`.

## Install

Copy the `scratchpad.koplugin/` folder into your KOReader `plugins/` directory:

| Device | Path |
| --- | --- |
| **Kobo** | `.adds/koreader/plugins/scratchpad.koplugin/` |
| **Kindle** | `koreader/plugins/scratchpad.koplugin/` |
| **Other** | `<koreader>/plugins/scratchpad.koplugin/` |

```bash
git clone https://github.com/lolwierd/scratchpad.koplugin.git
cp -R scratchpad.koplugin "/path/to/KOBOeReader/.adds/koreader/plugins/"
```

Then restart KOReader.

## Usage

Open it while reading a book:

- **Reader menu -> Navigation -> Scratchpad -> This book's scratchpad / Global scratchpad**

Or bind either action to a gesture:

- **Settings -> Taps and gestures -> Gesture manager -> (pick a gesture) -> "Scratchpad: this book" / "Scratchpad: global"**

Edit the note, then use the nav bar to **Save** (also saves on close) or **Reset** to the last saved content.

## Storage

| File | Contents |
| --- | --- |
| `koreader/scratchpads/<book-id>.txt` | per-book note |
| `koreader/scratchpads/_global.txt` | shared global note |

`<book-id>` is the book's partial MD5 when available, otherwise a sanitized filename.

## Notes

- Reader-only (`is_doc_only`) — a scratchpad is for notes while reading; it doesn't appear in the File Manager menu.

Personal project. No warranty.
