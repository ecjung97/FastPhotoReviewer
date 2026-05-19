import SwiftUI
import CoreImage
import ImageIO // CRITICAL: Apple's hardware-accelerated image engine
import QuickLookThumbnailing

struct LinkedPhotoAsset: Identifiable, Hashable {
    let id = UUID()
    let displayURL: URL
    let companionURLs: [URL]

    var isLinked: Bool {
        !companionURLs.isEmpty
    }

    var allURLs: [URL] {
        [displayURL] + companionURLs
    }
}

struct MovedFile {
    let originalURL: URL
    let sortedURL: URL
}

struct MoveAction {
    let movedFiles: [MovedFile]
    let asset: LinkedPhotoAsset
    let index: Int
}

struct ContentView: View {
    // MARK: - Core State
    @State private var workspaceRoot: URL?
    @State private var currentDirectory: URL?
    
    @State private var subfolders: [URL] = []
    @State private var photoFiles: [LinkedPhotoAsset] = []
    
    @State private var currentIndex: Int = 0
    @State private var undoHistory: [MoveAction] = []
    
    // MARK: - Image & Grid State
    @State private var isGridMode: Bool = false
    @State private var thumbnails: [URL: NSImage] = [:]
    @State private var currentHighResImage: NSImage? // Replaces AVPlayer
    @State private var isImageLoading: Bool = false
    
    @State private var gridIndex: Int = 0
    @State private var columnCount: Int = 1
    @State private var directoryRefreshID = UUID()
    @State private var isSelectionMode = false
    @State private var selectedPhotoIDs: Set<LinkedPhotoAsset.ID> = []

    let gridColumns = [GridItem(.adaptive(minimum: 240, maximum: 320), spacing: 24)]
    let sortingBins = ["to_delete", "1star", "2star", "3star", "4star", "5star"]
    
    // Formats tailored for Sony A7M4 and Galaxy S25U
    let validExtensions = ["jpg", "jpeg", "heic", "heif", "arw", "dng", "png", "tiff"]
    let fullResolutionExtensions = ["jpg", "jpeg", "png", "tiff"]
    let jpegExtensions = ["jpg", "jpeg"]
    let rawExtensions = ["arw", "dng"]
    let ciContext = CIContext()

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            if workspaceRoot != nil {
                if isGridMode {
                    buildGridView()
                        .id(directoryRefreshID)
                } else if !photoFiles.isEmpty {
                    VStack(spacing: 0) {
                        buildTopBar()
                        buildPhotoView()
                    }
                    .id(directoryRefreshID)
                } else {
                    VStack(spacing: 0) {
                        buildTopBar()
                        Text("No photos in this folder.")
                            .font(.title2)
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .id(directoryRefreshID)
                }
            } else {
                VStack(spacing: 20) {
                    Text("Select a Workspace to begin")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    
                    Button("Open Folder") {
                        selectWorkspace()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 1000, minHeight: 700)
        .background(buildShortcuts())
    }
    
    // MARK: - View Builders
    @ViewBuilder
    func buildPhotoView() -> some View {
        ZStack {
            if let image = currentHighResImage {
                VStack(spacing: 16) {
                    if let asset = currentPhotoAsset, asset.isLinked {
                        Label(linkedAssetMessage(for: asset), systemImage: "link")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(Color(white: 0.85))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.08), in: Capsule())
                    }

                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        // Optional: Add a subtle animation when switching photos
                        .transition(.opacity.animation(.easeInOut(duration: 0.15)))
                        .id(currentIndex) // Forces the transition to trigger
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            } else if isImageLoading {
                ProgressView()
                    .controlSize(.large)
            } else {
                Text("Failed to load image")
                    .foregroundColor(.red)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .edgesIgnoringSafeArea(.all)
    }
    
    @ViewBuilder
    func buildTopBar() -> some View {
        HStack(alignment: .center) {
            if let current = currentDirectory, let root = workspaceRoot, current != root {
                Button(action: navigateUp) {
                    Image(systemName: "chevron.left").fontWeight(.bold)
                }
                .buttonStyle(.plain)
                .foregroundColor(.white)
                .padding(.trailing, 8)
            }
            
            Text(topBarTitle)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            Spacer()

            if isGridMode, !photoFiles.isEmpty {
                Button(isSelectionMode ? "Cancel" : "Select") {
                    toggleSelectionMode()
                }
                .buttonStyle(.bordered)

                if isSelectionMode {
                    Button(selectionActionTitle) {
                        performSelectionAction()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedPhotoIDs.isEmpty)
                }
            }
            
            if isGridMode {
                Text(gridStatusText)
                    .font(.subheadline).foregroundColor(Color(white: 0.7))
            } else {
                Text(detailStatusText)
                    .font(.subheadline).foregroundColor(Color(white: 0.7))
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
        .background(.bar)
        .overlay(Divider().background(Color(white: 0.3)), alignment: .bottom)
    }

    var topBarTitle: String {
        if !isGridMode, currentIndex < photoFiles.count {
            return photoFiles[currentIndex].displayURL.lastPathComponent
        }

        return currentDirectory?.lastPathComponent ?? "Workspace"
    }

    var currentPhotoAsset: LinkedPhotoAsset? {
        guard currentIndex >= 0, currentIndex < photoFiles.count else { return nil }
        return photoFiles[currentIndex]
    }

    var detailStatusText: String {
        let linkedHint = currentPhotoAsset?.isLinked == true ? "Linked RAW+JPG" : "Single file"
        let undoHint = isInDeleteFolder ? "Z restore to parent" : "Z undo"
        return "\(linkedHint)  |  \(currentIndex + 1) of \(photoFiles.count)  |  G grid  Return open  X delete  1-5 stars  \(undoHint)"
    }

    var gridStatusText: String {
        let selectionText = isSelectionMode ? " • \(selectedPhotoIDs.count) selected" : ""
        return "\(subfolders.count) Folders • \(photoFiles.count) Photos\(selectionText)"
    }

    var selectionActionTitle: String {
        if isInDeleteFolder {
            return "Restore Selected (\(selectedPhotoIDs.count))"
        }

        return "Move to Delete (\(selectedPhotoIDs.count))"
    }

    var isInDeleteFolder: Bool {
        currentDirectory?.lastPathComponent == "to_delete"
    }
    
    @ViewBuilder
    func buildGridView() -> some View {
        GeometryReader { geo in
            ScrollViewReader { scrollProxy in
                ScrollView {
                    Spacer().frame(height: 70)
                    LazyVGrid(columns: gridColumns, spacing: 24) {
                        ForEach(Array(subfolders.enumerated()), id: \.element) { index, folder in
                            folderCell(folder: folder, index: index)
                        }
                        ForEach(Array(photoFiles.enumerated()), id: \.element.id) { vIndex, asset in
                            photoCell(asset: asset, globalIndex: subfolders.count + vIndex, vIndex: vIndex)
                        }
                    }
                    .padding(24)
                }
                .safeAreaInset(edge: .top) { buildTopBar() }
                .onChange(of: gridIndex) { oldValue, newValue in
                    withAnimation(.easeInOut(duration: 0.1)) { scrollProxy.scrollTo(newValue, anchor: .center) }
                }
            }
            .onAppear { calculateColumns(width: geo.size.width) }
            .onChange(of: geo.size.width) { oldWidth, newWidth in calculateColumns(width: newWidth) }
        }
    }
    
    // MARK: - Grid Cell Helpers
    @ViewBuilder
    func folderCell(folder: URL, index: Int) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Color(white: 0.12)
                Image(systemName: "folder.fill")
                    .resizable().scaledToFit().frame(width: 44, height: 44).foregroundColor(Color(white: 0.4))
            }
            .aspectRatio(16/9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(gridIndex == index ? Color.blue : Color.clear, lineWidth: 3))
            
            Text(folder.lastPathComponent).font(.system(size: 13, weight: .medium)).foregroundColor(Color(white: 0.8)).lineLimit(1)
        }
        .id(index)
        .onTapGesture(count: 2) { gridIndex = index; navigateDown(into: folder) }
        .onTapGesture(count: 1) { gridIndex = index }
    }
    
    @ViewBuilder
    func photoCell(asset: LinkedPhotoAsset, globalIndex: Int, vIndex: Int) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Color(white: 0.12)
                if let image = thumbnails[asset.displayURL] {
                    Image(nsImage: image).resizable().scaledToFit()
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .aspectRatio(16/9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(gridIndex == globalIndex ? Color.blue : Color.clear, lineWidth: 3))
            .overlay(alignment: .topTrailing) {
                VStack(alignment: .trailing, spacing: 8) {
                    if isSelectionMode {
                        Image(systemName: selectedPhotoIDs.contains(asset.id) ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundColor(selectedPhotoIDs.contains(asset.id) ? .green : Color.white.opacity(0.9))
                    }

                    if asset.isLinked {
                        Label("Linked", systemImage: "link")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .foregroundColor(.white)
                            .background(Color.black.opacity(0.7), in: Capsule())
                    }
                }
                .padding(10)
            }
            .task { await loadThumbnail(for: asset.displayURL) }
            
            VStack(spacing: 4) {
                Text(asset.displayURL.lastPathComponent).font(.system(size: 13, weight: .medium)).foregroundColor(Color(white: 0.8)).lineLimit(1).truncationMode(.middle)
                if asset.isLinked {
                    Text(linkedAssetMessage(for: asset))
                        .font(.caption)
                        .foregroundColor(Color(white: 0.6))
                        .lineLimit(1)
                }
            }
        }
        .id(globalIndex)
        .onTapGesture(count: 2) {
            guard !isSelectionMode else { return }
            gridIndex = globalIndex; isGridMode = false; currentIndex = vIndex; loadPhoto(at: asset.displayURL)
        }
        .onTapGesture(count: 1) {
            if isSelectionMode {
                toggleSelection(for: asset)
            } else {
                gridIndex = globalIndex
            }
        }
    }

    func linkedAssetMessage(for asset: LinkedPhotoAsset) -> String {
        let linkedExtensions = asset.companionURLs
            .map { $0.pathExtension.uppercased() }
            .sorted()
            .joined(separator: ", ")

        return "Linked to \(linkedExtensions)"
    }

    func toggleSelectionMode() {
        isSelectionMode.toggle()
        if !isSelectionMode {
            selectedPhotoIDs.removeAll()
        }
    }

    func toggleSelection(for asset: LinkedPhotoAsset) {
        if selectedPhotoIDs.contains(asset.id) {
            selectedPhotoIDs.remove(asset.id)
        } else {
            selectedPhotoIDs.insert(asset.id)
        }
    }

    func performSelectionAction() {
        if isInDeleteFolder {
            restoreSelectedAssetsToParentDirectory()
        } else {
            moveSelectedAssetsToDeleteFolder()
        }
    }

    // MARK: - The Keyboard Shortcut Hub
    func buildShortcuts() -> some View {
        VStack(spacing: 0) {
            Button("g") { toggleGridMode() }.keyboardShortcut("g", modifiers: [])
            Button("z") { undoLastAction() }.keyboardShortcut("z", modifiers: [])
            Button("Right") { handleRightArrow() }.keyboardShortcut(.rightArrow, modifiers: [])
            Button("Left") { handleLeftArrow() }.keyboardShortcut(.leftArrow, modifiers: [])
            Button("Down") { handleDownArrow() }.keyboardShortcut(.downArrow, modifiers: [])
            Button("Up") { handleUpArrow() }.keyboardShortcut(.upArrow, modifiers: [])
            Button("Return") { handleEnter() }.keyboardShortcut(.return, modifiers: [])
            Button("x") { handleSort("to_delete") }.keyboardShortcut("x", modifiers: [])
            Button("del") { handleSort("to_delete") }.keyboardShortcut(.delete, modifiers: [])
            Button("delFwd") { handleSort("to_delete") }.keyboardShortcut(.deleteForward, modifiers: [])
            Button("1") { handleSort("1star") }.keyboardShortcut("1", modifiers: [])
            Button("2") { handleSort("2star") }.keyboardShortcut("2", modifiers: [])
            Button("3") { handleSort("3star") }.keyboardShortcut("3", modifiers: [])
            Button("4") { handleSort("4star") }.keyboardShortcut("4", modifiers: [])
            Button("5") { handleSort("5star") }.keyboardShortcut("5", modifiers: [])
        }
        .opacity(0.001)
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
    }

    func handleRightArrow() { if isGridMode { moveGridSelection(by: 1) } else if !photoFiles.isEmpty { advanceToNextPhoto() } }
    func handleLeftArrow() { if isGridMode { moveGridSelection(by: -1) } else if !photoFiles.isEmpty { goToPreviousPhoto() } }
    func handleDownArrow() { if isGridMode { moveGridSelection(by: columnCount) } }
    func handleUpArrow() { if isGridMode { moveGridSelection(by: -columnCount) } }
    func handleEnter() { if isGridMode { handleGridEnter() } }
    func handleSort(_ bin: String) { if isGridMode { sortGridCurrent(to: bin) } else if !photoFiles.isEmpty { sortCurrent(to: bin) } }

    // MARK: - Navigation Logic
    func calculateColumns(width: CGFloat) {
        let cols = Int((width - 48 + 24) / (240 + 24))
        self.columnCount = max(1, cols)
    }

    func selectWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.prompt = "Select Workspace"
        if panel.runModal() == .OK {
            if let url = panel.url { workspaceRoot = url; ensureDestinationFoldersExist(in: url); scanDirectory(at: url) }
        }
    }
    
    func navigateDown(into folder: URL) { scanDirectory(at: folder) }
    func navigateUp() {
        guard let current = currentDirectory, let root = workspaceRoot else { return }
        if current != root { scanDirectory(at: current.deletingLastPathComponent()) }
    }
    
    func ensureDestinationFoldersExist(in baseFolder: URL) {
        for folder in sortingBins { try? FileManager.default.createDirectory(at: baseFolder.appendingPathComponent(folder), withIntermediateDirectories: true) }
    }
    
    func scanDirectory(at targetFolder: URL) {
        currentHighResImage = nil
        thumbnails.removeAll()
        isImageLoading = false
        currentDirectory = targetFolder
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: targetFolder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            var foundFolders: [URL] = []
            var foundPhotos: [URL] = []
            
            for url in contents {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true { foundFolders.append(url) }
                else if validExtensions.contains(url.pathExtension.lowercased()) { foundPhotos.append(url) }
            }
            
            subfolders = foundFolders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            photoFiles = buildLinkedPhotoAssets(from: foundPhotos)
            
            currentIndex = 0; gridIndex = 0; undoHistory.removeAll(); isGridMode = true
            isSelectionMode = false
            selectedPhotoIDs.removeAll()
            directoryRefreshID = UUID()
        } catch { print("Error scanning: \(error)") }
    }

    func buildLinkedPhotoAssets(from urls: [URL]) -> [LinkedPhotoAsset] {
        let sortedURLs = urls.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending })
        let groupedURLs = Dictionary(grouping: sortedURLs) { normalizedAssetKey(for: $0) }
        var assets: [LinkedPhotoAsset] = []

        for urls in groupedURLs.values {
            let sortedGroup = urls.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending })

            if let jpegURL = sortedGroup.first(where: { jpegExtensions.contains($0.pathExtension.lowercased()) }) {
                let companions = sortedGroup.filter { $0 != jpegURL }
                assets.append(LinkedPhotoAsset(displayURL: jpegURL, companionURLs: companions))
            } else {
                for url in sortedGroup {
                    assets.append(LinkedPhotoAsset(displayURL: url, companionURLs: []))
                }
            }
        }

        return assets.sorted(by: { $0.displayURL.lastPathComponent.localizedStandardCompare($1.displayURL.lastPathComponent) == .orderedAscending })
    }

    func normalizedAssetKey(for url: URL) -> String {
        let extensionlessName = url.deletingPathExtension().lastPathComponent
        let normalizedName = extensionlessName.replacingOccurrences(of: "(?i)[ _-](raw|edit|large|small)$", with: "", options: .regularExpression)
        return normalizedName.lowercased()
    }
    
    // MARK: - Hardware-Accelerated Image Engine (ImageIO)
    func loadThumbnail(for url: URL) async {
        if thumbnails[url] != nil { return }

        if let quickLookThumbnail = await loadQuickLookThumbnail(for: url) {
            await MainActor.run { self.thumbnails[url] = quickLookThumbnail }
            return
        }
        
        // This extracts embedded RAW thumbnails without decoding the massive RAW file
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 400, // Keeps RAM usage near zero
            kCGImageSourceShouldCacheImmediately: true
        ]
        
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            await MainActor.run { self.thumbnails[url] = NSImage(cgImage: cgImage, size: .zero) }
        }
    }

    func loadQuickLookThumbnail(for url: URL) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 400, height: 400),
            scale: NSScreen.main?.backingScaleFactor ?? 2.0,
            representationTypes: .thumbnail
        )

        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumbnail, error in
                guard error == nil, let thumbnail else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: thumbnail.nsImage)
            }
        }
    }
    
    func loadPhoto(at url: URL) {
        isImageLoading = true
        
        Task {
            let fileExtension = url.pathExtension.lowercased()
            let image = loadDisplayImage(for: url, fileExtension: fileExtension)
            
            await MainActor.run {
                if let image {
                    self.currentHighResImage = image
                }
                self.isImageLoading = false
            }
        }
    }

    func loadDisplayImage(for url: URL, fileExtension: String) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

        if fullResolutionExtensions.contains(fileExtension) {
            let options: [CFString: Any] = [
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceShouldAllowFloat: true
            ]

            if let cgImage = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) {
                return makeOrientedImage(from: cgImage, source: source)
            }
        }

        // RAW/HEIC benefit from display-sized decoding to keep navigation responsive.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 3000,
            kCGImageSourceShouldCacheImmediately: true
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: .zero)
    }

    func makeOrientedImage(from cgImage: CGImage, source: CGImageSource) -> NSImage {
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let orientationValue = properties[kCGImagePropertyOrientation] as? UInt32,
            orientationValue != 1
        else {
            return NSImage(cgImage: cgImage, size: .zero)
        }

        let orientedImage = CIImage(cgImage: cgImage).oriented(forExifOrientation: Int32(orientationValue))

        guard let transformedCGImage = ciContext.createCGImage(orientedImage, from: orientedImage.extent) else {
            return NSImage(cgImage: cgImage, size: .zero)
        }

        return NSImage(cgImage: transformedCGImage, size: .zero)
    }
    
    func toggleGridMode() {
        if isGridMode {
            if gridIndex >= subfolders.count {
                isGridMode = false
                currentIndex = gridIndex - subfolders.count
                loadPhoto(at: photoFiles[currentIndex].displayURL)
            } else { NSSound.beep() }
        } else {
            isGridMode = true
            currentHighResImage = nil // Free memory
            gridIndex = subfolders.count + currentIndex
        }
    }
    
    // MARK: - Navigation Engines
    func moveGridSelection(by offset: Int) {
        let totalItems = subfolders.count + photoFiles.count
        guard totalItems > 0 else { return }
        gridIndex = max(0, min(gridIndex + offset, totalItems - 1))
    }
    
    func handleGridEnter() {
        if gridIndex < subfolders.count { navigateDown(into: subfolders[gridIndex]) }
        else {
            let vIndex = gridIndex - subfolders.count
            if vIndex >= 0 && vIndex < photoFiles.count {
                currentIndex = vIndex; isGridMode = false; loadPhoto(at: photoFiles[currentIndex].displayURL)
            }
        }
    }
    
    func advanceToNextPhoto() {
        if currentIndex < photoFiles.count - 1 {
            currentIndex += 1
            if !isGridMode { loadPhoto(at: photoFiles[currentIndex].displayURL) }
        }
    }
    
    func goToPreviousPhoto() {
        if currentIndex > 0 {
            currentIndex -= 1
            if !isGridMode { loadPhoto(at: photoFiles[currentIndex].displayURL) }
        }
    }
    
    // MARK: - Sorting Engine
    func sortGridCurrent(to folderName: String) {
        if gridIndex < subfolders.count { NSSound.beep(); return }
        currentIndex = gridIndex - subfolders.count
        sortCurrent(to: folderName)
        let totalItems = subfolders.count + photoFiles.count
        gridIndex = totalItems == 0 ? 0 : min(gridIndex, totalItems - 1)
    }
    
    func sortCurrent(to folderName: String) {
        guard let root = workspaceRoot, currentIndex < photoFiles.count else { return }
        let asset = photoFiles[currentIndex]
        
        do {
            var movedFiles: [MovedFile] = []

            for originalURL in asset.allURLs {
                let sortedURL = root.appendingPathComponent(folderName).appendingPathComponent(originalURL.lastPathComponent)
                try FileManager.default.moveItem(at: originalURL, to: sortedURL)
                movedFiles.append(MovedFile(originalURL: originalURL, sortedURL: sortedURL))
            }

            undoHistory.append(MoveAction(movedFiles: movedFiles, asset: asset, index: currentIndex))
            photoFiles.remove(at: currentIndex)
            thumbnails.removeValue(forKey: asset.displayURL)
            
            if photoFiles.isEmpty {
                currentHighResImage = nil; isGridMode = true
            } else {
                if currentIndex >= photoFiles.count { currentIndex = photoFiles.count - 1 }
                if !isGridMode { loadPhoto(at: photoFiles[currentIndex].displayURL) }
            }
        } catch { print("Failed to move file: \(error)") }
    }
    
    func undoLastAction() {
        guard let lastAction = undoHistory.popLast() else {
            if isInDeleteFolder {
                restoreCurrentAssetToParentDirectory()
            } else {
                NSSound.beep()
            }
            return
        }

        do {
            for movedFile in lastAction.movedFiles.reversed() {
                try FileManager.default.moveItem(at: movedFile.sortedURL, to: movedFile.originalURL)
            }

            photoFiles.insert(lastAction.asset, at: lastAction.index)
            
            if !isGridMode {
                currentIndex = lastAction.index
                loadPhoto(at: photoFiles[currentIndex].displayURL)
            } else { gridIndex = subfolders.count + lastAction.index }
        } catch { print("Failed to undo: \(error)") }
    }

    func restoreCurrentAssetToParentDirectory() {
        guard let currentDirectory, currentIndex >= 0, currentIndex < photoFiles.count else {
            NSSound.beep()
            return
        }

        let parentDirectory = currentDirectory.deletingLastPathComponent()
        let asset = photoFiles[currentIndex]

        do {
            for currentURL in asset.allURLs {
                let restoredURL = parentDirectory.appendingPathComponent(currentURL.lastPathComponent)
                try FileManager.default.moveItem(at: currentURL, to: restoredURL)
            }

            photoFiles.remove(at: currentIndex)
            thumbnails.removeValue(forKey: asset.displayURL)

            if photoFiles.isEmpty {
                currentHighResImage = nil
                isGridMode = true
            } else {
                if currentIndex >= photoFiles.count { currentIndex = photoFiles.count - 1 }
                if !isGridMode { loadPhoto(at: photoFiles[currentIndex].displayURL) }
            }
        } catch {
            print("Failed to restore file: \(error)")
        }
    }

    func restoreSelectedAssetsToParentDirectory() {
        guard isInDeleteFolder, let currentDirectory else {
            NSSound.beep()
            return
        }

        let selectedAssets = photoFiles.filter { selectedPhotoIDs.contains($0.id) }
        guard !selectedAssets.isEmpty else {
            NSSound.beep()
            return
        }

        let parentDirectory = currentDirectory.deletingLastPathComponent()

        do {
            for asset in selectedAssets {
                for currentURL in asset.allURLs {
                    let restoredURL = parentDirectory.appendingPathComponent(currentURL.lastPathComponent)
                    try FileManager.default.moveItem(at: currentURL, to: restoredURL)
                }
            }

            photoFiles.removeAll { selectedPhotoIDs.contains($0.id) }
            for asset in selectedAssets {
                thumbnails.removeValue(forKey: asset.displayURL)
            }

            selectedPhotoIDs.removeAll()
            isSelectionMode = false
            currentHighResImage = nil
            currentIndex = 0
            gridIndex = 0
        } catch {
            print("Failed to restore selected files: \(error)")
        }
    }

    func moveSelectedAssetsToDeleteFolder() {
        guard let root = workspaceRoot, !isInDeleteFolder else {
            NSSound.beep()
            return
        }

        let selectedAssets = photoFiles.filter { selectedPhotoIDs.contains($0.id) }
        guard !selectedAssets.isEmpty else {
            NSSound.beep()
            return
        }

        let deleteDirectory = root.appendingPathComponent("to_delete")

        do {
            for asset in selectedAssets {
                for originalURL in asset.allURLs {
                    let sortedURL = deleteDirectory.appendingPathComponent(originalURL.lastPathComponent)
                    try FileManager.default.moveItem(at: originalURL, to: sortedURL)
                }
            }

            photoFiles.removeAll { selectedPhotoIDs.contains($0.id) }
            for asset in selectedAssets {
                thumbnails.removeValue(forKey: asset.displayURL)
            }

            selectedPhotoIDs.removeAll()
            isSelectionMode = false
            currentHighResImage = nil
            currentIndex = 0
            gridIndex = 0
        } catch {
            print("Failed to move selected files to delete: \(error)")
        }
    }
}
