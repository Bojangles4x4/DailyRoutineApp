import Foundation
import SwiftUI
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
        weak var webView: WKWebView?

        init(model: AppModel) {
            self.model = model
        }

        func connectWatchEvents() {
            model.watch.onEvent = { [weak self] event in
                self?.emit(name: "watch.event", value: event)
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
                do {
                    try model.watch.update(context: context)
                    emit(name: "watch.context.updated", value: ["updated": true])
                } catch {
                    emitError(error.localizedDescription)
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            emit(
                name: "native.ready",
                value: [
                    "healthAvailable": model.health.isAvailable,
                    "watchReachable": model.watch.isReachable
                ]
            )
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
    }
}

private extension JSONEncoder {
    static var bridge: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
