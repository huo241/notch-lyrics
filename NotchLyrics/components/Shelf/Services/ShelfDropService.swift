//
//  ShelfDropService.swift
//  Notch Lyrics
//
//  Created by Alexander on 2025-09-26.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

struct ShelfDropService {
    /// Direct URL path for the window-level drop handler.
    ///
    /// The AppKit drop already hands us real file URLs, so rebuilding an
    /// `NSItemProvider` from each one and loading it back again only adds
    /// failure modes (the provider round-trip can lose the file-URL
    /// representation for some types). Bookmarks are created straight from
    /// the URL, exactly like `processProvider` does.
    static func items(fromURLs urls: [URL]) async -> [ShelfItem] {
        var results: [ShelfItem] = []

        for url in urls {
            if url.isFileURL {
                if let bookmark = createBookmark(for: url) {
                    results.append(await ShelfItem(kind: .file(bookmark: bookmark), isTemporary: false))
                }
            } else {
                results.append(await ShelfItem(kind: .link(url: url), isTemporary: false))
            }
        }

        return results
    }

    static func items(from providers: [NSItemProvider]) async -> [ShelfItem] {
        var results: [ShelfItem] = []

        for provider in providers {
            if let item = await processProvider(provider) {
                results.append(item)
            }
        }

        return results
    }
    
    private static func processProvider(_ provider: NSItemProvider) async -> ShelfItem? {
        if let actualFileURL = await provider.extractFileURL() {
            if let bookmark = createBookmark(for: actualFileURL) {
                return await ShelfItem(kind: .file(bookmark: bookmark), isTemporary: false)
            }
            return nil
        }
        
        if let url = await provider.extractURL() {
            if url.isFileURL {
                if let bookmark = createBookmark(for: url) {
                    return await ShelfItem(kind: .file(bookmark: bookmark), isTemporary: false)
                }
            } else {
                return await ShelfItem(kind: .link(url: url), isTemporary: false)
            }
            return nil
        }
        
        if let text = await provider.extractText() {
            return await ShelfItem(kind: .text(string: text), isTemporary: false)
        }
        
        if let data = await provider.loadData() {
            if let tempDataURL = await TemporaryFileStorageService.shared.createTempFile(for: .data(data, suggestedName: provider.suggestedName)),
               let bookmark = createBookmark(for: tempDataURL) {
                return await ShelfItem(kind: .file(bookmark: bookmark), isTemporary: true)
            }
            return nil
        }
        
        if let fileURL = await provider.extractItem() {
            if let bookmark = createBookmark(for: fileURL) {
                return await ShelfItem(kind: .file(bookmark: bookmark), isTemporary: false)
            }
        }
        
        return nil
    }
    
    private static func createBookmark(for url: URL) -> Data? {
        return (try? Bookmark(url: url))?.data
    }
}

