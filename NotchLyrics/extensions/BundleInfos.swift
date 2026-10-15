//
//  BundleInfos.swift
//  Notch Lyrics
//
//  Created by Richard Kunkli on 08/08/2024.
//

import Foundation

extension Bundle {
    var releaseVersionNumber: String? {
        return infoDictionary?["CFBundleShortVersionString"] as? String
    }
    var buildVersionNumber: String? {
        return infoDictionary?["CFBundleVersion"] as? String
    }
}
