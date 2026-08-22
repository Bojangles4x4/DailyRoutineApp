import Foundation
import SwiftUI
import UIKit
import WebKit

struct WebAppView: UIViewRepresentable {
    @ObservedObject var model: AppModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.userContentController.add(context.coordinator, name: "dailyRoutine")

        let bridgeScript = WKUserScript(
            source: """
            window.DailyRoutineNative = {
              postMessage(message) {
                window.webkit.messageHandlers.dailyRoutine.postMessage(message);
              }
            };
            window.dispatchEvent(new CustomEvent('dailyRoutine:native-ready'));
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        configuration.userContentController.addUserScript(bridgeScript)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        context.coordinator.webView = webView
        context.coordinator.connectWatchEvents()

        guard let indexURL = Bundle.main.url(forResource: "index", withExtension: "html") else {
            assertionFailure("The bundled web app is missing index.html")
            return webView
        }
        webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        private let model: AppModel
        private var isWebAppReady = false
        private var pendingWatchEvents: [WatchEvent] = []
        private var processedWatchEventIDs = Set<UUID>()
        weak var webView: WKWebView?

        init(model: AppModel) {
            self.model = model
        }

        func connectWatchEvents() {
            model.watch.onEvent = { [weak self] event in
                self?.receiveWatchEvent(event)
            }
        }

        private func receiveWatchEvent(_ event: WatchEvent) {
            guard processedWatchEventIDs.insert(event.id).inserted else { return }
            if isWebAppReady {
                emit(name: "watch.event", value: event)
            } else {
                pendingWatchEvents.append(event)
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard
                let payload = message.body as? [String: Any],
                let rawAction = payload["action"] as? String,
                let action = NativeBridgeAction(rawValue: rawAction)
            else {
                emitError("The native request was not recognized.")
                return
            }

            switch action {
            case .requestHealthAuthorization:
                Task {
                    do {
                        try await model.health.requestAuthorization()
                        emit(name: "health.authorization.completed", value: ["requested": true])
                    } catch {
                        emitError(error.localizedDescription)
                    }
                }
            case .requestHealthSummary:
                Task {
                    do {
                        emit(name: "health.summary", value: try await model.health.fetchSummary())
                    } catch {
                        emitError(error.localizedDescription)
                    }
                }
            case .updateWatchContext:
                guard
                    let value = payload["value"],
                    JSONSerialization.isValidJSONObject(value),
                    let data = try? JSONSerialization.data(withJSONObject: value),
                    let context = try? JSONDecoder().decode(WatchRoutineContext.self, from: data)
                else {
                    emitError("The Watch context was not valid.")
                    return
                }
                let updated = model.watch.update(context: context)
                emit(name: "watch.context.updated", value: ["updated": updated, "queued": !updated])
            case .shareText:
                guard
                    let value = payload["value"] as? [String: Any],
                    let text = value["text"] as? String,
                    !text.isEmpty
                else {
                    emitError("The report was empty and could not be shared.")
                    return
                }
                presentShareSheet(title: value["title"] as? String, text: text)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isWebAppReady = true
            emit(
                name: "native.ready",
                value: [
                    "healthAvailable": model.health.isAvailable,
                    "watchReachable": model.watch.isReachable,
                    "watchInstalled": model.watch.isWatchAppInstalled
                ]
            )
            pendingWatchEvents.forEach { emit(name: "watch.event", value: $0) }
            pendingWatchEvents.removeAll()
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard
                navigationAction.navigationType == .linkActivated,
                let url = navigationAction.request.url,
                let scheme = url.scheme?.lowercased(),
                scheme == "http" || scheme == "https"
            else {
                decisionHandler(.allow)
                return
            }

            UIApplication.shared.open(url)
            decisionHandler(.cancel)
        }

        private func emit<T: Encodable>(name: String, value: T) {
            guard
                let data = try? JSONEncoder.bridge.encode(value),
                let json = String(data: data, encoding: .utf8)
            else { return }

            let escapedName = name.replacingOccurrences(of: "'", with: "\\'")
            let script = "window.dispatchEvent(new CustomEvent('dailyRoutine:native', { detail: { name: '\(escapedName)', value: \(json) } }));"
            webView?.evaluateJavaScript(script)
        }

        private func emitError(_ message: String) {
            emit(name: "native.error", value: ["message": message])
        }

        private func presentShareSheet(title: String?, text: String) {
            let controller = UIActivityViewController(activityItems: [text], applicationActivities: nil)
            if let title, !title.isEmpty {
                controller.setValue(title, forKey: "subject")
            }
            if let popover = controller.popoverPresentationController, let webView {
                popover.sourceView = webView
                popover.sourceRect = CGRect(x: webView.bounds.midX, y: webView.bounds.maxY - 1, width: 1, height: 1)
            }
            guard let presenter = topViewController(from: webView?.window?.rootViewController) else {
                emitError("The share options could not be opened.")
                return
            }
            presenter.present(controller, animated: true)
        }

        private func topViewController(from controller: UIViewController?) -> UIViewController? {
            if let presented = controller?.presentedViewController {
                return topViewController(from: presented)
            }
            if let navigation = controller as? UINavigationController {
                return topViewController(from: navigation.visibleViewController)
            }
            if let tabs = controller as? UITabBarController {
                return topViewController(from: tabs.selectedViewController)
            }
            return controller
        }
    }
}

private extension JSONEncoder {
    static var bridge: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
