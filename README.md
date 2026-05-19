# FastPhotoReviewer

FastPhotoReviewer is a macOS SwiftUI app for quickly reviewing, sorting, and restoring photo files from a selected workspace folder. It is built for keyboard-first culling workflows and keeps paired JPG/RAW files linked so you can review the fast JPG preview while moving the matching RAW file with it.

## Features

- Folder-based photo review with grid and detail views.
- Automatic creation of sorting folders: `to_delete`, `1star`, `2star`, `3star`, `4star`, and `5star`.
- Keyboard shortcuts for fast navigation and sorting.
- JPG/RAW linking by normalized base filename.
- Linked-file badges in the grid and detail view.
- Quick Look thumbnails for more realistic macOS-style previews.
- EXIF orientation handling for detail images.
- Batch selection in grid view for moving multiple photos to `to_delete`.
- Batch restore from `to_delete` back to the parent directory.
- Undo support for the most recent in-session move.

## Supported File Types

The app currently scans these extensions:

- `jpg`
- `jpeg`
- `heic`
- `heif`
- `arw`
- `dng`
- `png`
- `tiff`

JPG/JPEG files are preferred as the visible representative when paired with RAW files. RAW files without a JPG companion still appear as their own items.

## Requirements

- macOS app target
- Xcode
- SwiftUI
- Project deployment target: macOS `26.4`

The app uses Apple frameworks only:

- `SwiftUI`
- `CoreImage`
- `ImageIO`
- `QuickLookThumbnailing`

## Getting Started

1. Open `FastPhotoReviewer.xcodeproj` in Xcode.
2. Select the `FastPhotoReviewer` scheme.
3. Build and run the app.
4. Click `Open Folder`.
5. Select the workspace folder that contains your photos.

When a workspace is selected, the app creates these folders if they do not already exist:

```text
to_delete/
1star/
2star/
3star/
4star/
5star/
```

These folders are shown in the grid and can be opened like normal folders.

## Workspace Workflow

FastPhotoReviewer treats the selected folder as the workspace root. Sorting actions move files into folders under that root.

Example workspace:

```text
Photoshoot/
├── DSC001.JPG
├── DSC001.ARW
├── DSC002.JPG
├── DSC002.ARW
├── to_delete/
├── 1star/
├── 2star/
├── 3star/
├── 4star/
└── 5star/
```

If `DSC001.JPG` and `DSC001.ARW` share the same base name, the app displays `DSC001.JPG` and marks it as linked. Moving that visible JPG also moves the paired RAW file.

## Linked JPG/RAW Behavior

The app groups files by normalized base filename. For example:

```text
DSC001.JPG
DSC001.ARW
```

becomes one linked asset in the UI.

The visible file is the JPG/JPEG. Companion files are moved with it during sorting, batch delete moves, and restore actions.

The app also strips common suffixes while matching:

```text
_raw
-raw
 raw
_edit
-edit
 edit
_large
-large
 large
_small
-small
 small
```

## Keyboard Shortcuts

| Shortcut | Action |
| --- | --- |
| `G` | Toggle between grid and detail view |
| `Return` | Open the selected grid photo or folder |
| `Right Arrow` | Move right in grid, or next photo in detail view |
| `Left Arrow` | Move left in grid, or previous photo in detail view |
| `Down Arrow` | Move down by one grid row |
| `Up Arrow` | Move up by one grid row |
| `X` | Move current photo or linked asset to `to_delete` |
| `Delete` | Move current photo or linked asset to `to_delete` |
| `1` | Move current photo or linked asset to `1star` |
| `2` | Move current photo or linked asset to `2star` |
| `3` | Move current photo or linked asset to `3star` |
| `4` | Move current photo or linked asset to `4star` |
| `5` | Move current photo or linked asset to `5star` |
| `Z` | Undo the last move in the current session |

When viewing `to_delete`, `Z` restores the current photo or linked asset back to the parent directory if there is no in-session move to undo.

## Batch Actions

Batch actions are available in grid view.

### Move Multiple Photos to `to_delete`

1. Open a folder in grid view.
2. Click `Select`.
3. Click each photo you want to select.
4. Click `Move to Delete`.

Linked JPG/RAW assets move together.

### Restore Multiple Photos from `to_delete`

1. Open the `to_delete` folder.
2. Click `Select`.
3. Click each photo you want to restore.
4. Click `Restore Selected`.

The selected files are moved back to the parent directory.

## Image Loading

Grid thumbnails use `QuickLookThumbnailing` first so previews usually match Finder and macOS thumbnail rendering. If Quick Look cannot create a thumbnail, the app falls back to ImageIO.

Detail view uses:

- Full-resolution loading for `jpg`, `jpeg`, `png`, and `tiff`.
- Display-sized ImageIO thumbnail decoding for RAW/HEIC-style formats to keep navigation responsive.

EXIF orientation metadata is applied so rotated photos display correctly.

## File Safety Notes

FastPhotoReviewer moves files on disk. It does not copy them.

Important behavior:

- Sorting moves files into folders under the workspace root.
- Moving to `to_delete` does not delete files from disk; it moves them into the `to_delete` folder.
- Restoring from `to_delete` moves files back to the parent directory.
- Destination filename collisions are not automatically resolved. If a file with the same name already exists in the destination folder, the move may fail.
- Undo history is in-memory and resets when navigating into a different folder.

Keep a backup of important photo shoots before using any bulk file-moving workflow.

## Project Structure

```text
FastPhotoReviewer/
├── FastPhotoReviewer.xcodeproj/
├── FastPhotoReviewer/
│   ├── Assets.xcassets/
│   ├── ContentView.swift
│   └── FastPhotoReviewerApp.swift
├── README.md
└── LICENSE
```

## Development

The app is currently implemented in a small SwiftUI codebase:

- `FastPhotoReviewerApp.swift` defines the app entry point.
- `ContentView.swift` contains the UI, directory scanning, thumbnail loading, linked-asset grouping, keyboard shortcuts, sorting, undo, and batch actions.

To verify changes, build the project in Xcode.

## License

This project is available under the MIT License. See [LICENSE](LICENSE) for details.
