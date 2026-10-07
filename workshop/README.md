# Workshop release

Everything for publishing AEGIS-M on the Steam Workshop. This folder isn't
packed into the mod.

## What goes where

| Field | Use |
|---|---|
| Title | `AEGIS-M - Integrated Air Defence Framework` |
| Description | The whole of [description.bbcode](description.bbcode), pasted into the item's description on Steam (it is Steam's own formatting). |
| Preview image | [preview.png](preview.png) (1024 x 1024, 72 KB; Steam wants it square and under 1 MB). |
| Mod content | `.hemttout\release` after `hemtt release` (or `tools\release.cmd`): `addons`, `keys`, `mod.cpp`, the logos, `README.md`, `LICENSE`. |
| Tags | Data type **Mod**; mod type **Mechanics** and **Modules** (pick what Publisher offers). |
| Required items | **CBA_A3** (450814997). Zeus Enhanced (1779063631) is optional, so it is only named in the description. |
| Visibility | **Private** or **Unlisted** for the first upload, to check the page; then Public. |
| First change note | `Initial release (v0.1.0).` |

## Before the first upload

- **Make the GitHub repository public**, or the three GitHub links in the
  description lead nowhere for everyone but you. (It is private as of
  2026-10-07.) If it stays private, take the Links section out.
- Build what you upload: `tools\release.cmd` (which also makes the GitHub
  release) or just `hemtt release`.

## First upload (once, by hand)

The command-line publisher can only update an item that exists, so the
first upload is done in the app.

1. Start Steam, logged in as the account that will own the item.
2. Arma 3 Tools > **Publisher**.
3. Mod content: `C:\GitHub\AEGIS-M\.hemttout\release`.
4. Name, a one-line description (the full one is pasted on Steam after),
   the preview image, the tags, visibility, the change note. Publish.
5. On the item's Steam page: **Edit title & description** and paste
   `description.bbcode`; **Add/Remove Required Items** and add CBA_A3.
6. Note the item's ID: the number after `?id=` in its address.

## Updates (can be scripted)

With Steam running and logged in as the owner:

```
"D:\Steam Library\steamapps\common\Arma 3 Tools\Publisher\PublisherCmd.exe" update /id:<ITEM ID> /changeNote:"v0.1.1: ..." /path:"C:\GitHub\AEGIS-M\.hemttout\release"
```

`/changeNoteFile:<text file>` instead of `/changeNote` for a longer note.
It returns 0 when the upload worked. Once the item has an ID,
`tools\release.cmd` can be given a step that does this after the GitHub
release, with the same notes.
