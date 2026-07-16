import AgentUsageCore
import AppKit
import WebKit

@MainActor
final class CodexWebSessionWindow: NSObject, WKNavigationDelegate {
    private static let usageExtractionScript = """
    (() => {
      const terms = /reset|credit|expire|expiry|expires|valid until|过期|到期/i;
      const lines = [];

      if (document.body && document.body.innerText) {
        lines.push(document.body.innerText);
      }

      const nodes = Array.from(document.querySelectorAll('time,[aria-label],[title]'));
      for (const node of nodes) {
        const parts = [];
        const tag = node.tagName ? node.tagName.toLowerCase() : 'node';
        const text = (node.innerText || node.textContent || '').trim();
        const context = node.closest('section,article,li,div')?.innerText?.trim() || '';

        for (const name of ['datetime', 'aria-label', 'title', 'data-date', 'data-testid']) {
          const value = node.getAttribute && node.getAttribute(name);
          if (value) {
            parts.push(`${name}: ${value}`);
          }
        }

        if (text) {
          parts.push(`text: ${text}`);
        }
        if (context && context.length < 1200 && terms.test(context)) {
          parts.push(`context: ${context}`);
        }

        const line = `[${tag}] ${parts.join(' | ')}`.trim();
        if (parts.length > 0 && terms.test(line)) {
          lines.push(line.slice(0, 2000));
        }
      }

      return lines.join('\\n\\n').slice(0, 200000);
    })()
    """

    private let onSnapshotUpdated: () -> Void
    private var window: NSWindow?
    private var webView: WKWebView?
    private var statusLabel: NSTextField?
    private var timer: Timer?

    init(onSnapshotUpdated: @escaping () -> Void) {
        self.onSnapshotUpdated = onSnapshotUpdated
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        self.webView = webView

        let statusLabel = NSTextField(labelWithString: "Sign in to Codex here to inspect the official page. Dashboard usage still comes only from OAuth API or CLI RPC.")
        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byWordWrapping
        self.statusLabel = statusLabel

        let syncButton = NSButton(title: "Sync now", target: self, action: #selector(syncNow))
        syncButton.bezelStyle = .rounded

        let toolbar = NSStackView(views: [statusLabel, syncButton])
        toolbar.orientation = .horizontal
        toolbar.alignment = .centerY
        toolbar.spacing = 12
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        syncButton.setContentHuggingPriority(.required, for: .horizontal)

        let root = NSStackView(views: [toolbar, webView])
        root.orientation = .vertical
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        webView.heightAnchor.constraint(greaterThanOrEqualToConstant: 620).isActive = true

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Codex Web Debug"
        window.contentView = root
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        self.window = window

        guard let codexURL = URL(string: "https://chatgpt.com/codex/") else {
            self.statusLabel?.stringValue = "Invalid Codex URL."
            return
        }
        webView.load(URLRequest(url: codexURL))
        startTimer()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        extractUsage()
    }

    @objc private func syncNow() {
        extractUsage()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.extractUsage()
            }
        }
    }

    private func extractUsage() {
        guard let webView else { return }

        webView.evaluateJavaScript(Self.usageExtractionScript) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }

                if let error {
                    self.statusLabel?.stringValue = "Codex sync failed: \(error.localizedDescription)"
                    return
                }

                guard let text = result as? String, text.isEmpty == false else {
                    self.statusLabel?.stringValue = "Codex page text is empty. Finish login, then click Sync now."
                    return
                }

                let snapshot = CodexUsageTextParser.snapshot(from: text)
                self.statusLabel?.stringValue = snapshot.health == .ready
                    ? "Official page text was readable. Dashboard usage still comes only from OAuth API or CLI RPC."
                    : "Signed in page loaded, but no usage bars were detected yet."
                self.onSnapshotUpdated()
            }
        }
    }
}
