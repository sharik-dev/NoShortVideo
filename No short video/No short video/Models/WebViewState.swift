//
//  WebViewState.swift
//  No short video
//
//  Created by Sharik Mohamed on 05/03/2026.
//

import Combine
import Foundation

/// Observable state of the WKWebView, consumed by the toolbar and other UI.
final class WebViewState: ObservableObject {

    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var isLoading: Bool = false
    @Published var currentURL: URL?
    @Published var pageTitle: String = ""
}
