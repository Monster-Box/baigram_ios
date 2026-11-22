import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext

public final class AuthorizationSequenceServerController: ViewController {
    private var controllerNode: AuthorizationSequenceServerControllerNode {
        return self.displayNode as! AuthorizationSequenceServerControllerNode
    }

    private var validLayout: ContainerViewLayout?

    private let presentationData: PresentationData
    private let account: UnauthorizedAccount
    private let initialServerId: String

    public var completed: (() -> Void)?

    private var inProgress = false {
        didSet {
            self.controllerNode.inProgress = self.inProgress
        }
    }

    public init(account: UnauthorizedAccount, presentationData: PresentationData) {
        self.account = account
        self.presentationData = presentationData
        self.initialServerId = BaigramServerConfig.current(accountId: account.id).id

        super.init(navigationBarPresentationData: NavigationBarPresentationData(theme: AuthorizationSequenceController.navigationBarTheme(presentationData.theme), strings: NavigationBarStrings(presentationStrings: presentationData.strings)))

        self.supportedOrientations = ViewControllerSupportedOrientations(regularSize: .all, compactSize: .portrait)

        self.hasActiveInput = true

        self.statusBar.statusBarStyle = presentationData.theme.intro.statusBarStyle.style
        self.attemptNavigation = { _ in
            return false
        }
        self.navigationBar?.backPressed = { [weak self] in
            self?.dismiss()
        }
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func loadDisplayNode() {
        self.displayNode = AuthorizationSequenceServerControllerNode(strings: self.presentationData.strings, theme: self.presentationData.theme, currentServerId: self.initialServerId)
        self.displayNodeDidLoad()

        self.controllerNode.view.disableAutomaticKeyboardHandling = [.forward, .backward]

        self.controllerNode.proceed = { [weak self] id in
            self?.requestServer(id: id)
        }
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        self.controllerNode.activateInput()
    }

    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)

        self.validLayout = layout
        self.controllerNode.containerLayoutUpdated(layout, navigationBarHeight: self.navigationLayout(layout: layout).navigationFrame.maxY, transition: transition)
    }

    private func requestServer(id: String) {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            self.controllerNode.showError("Please enter a server ID")
            return
        }
        if trimmed.range(of: "^[\\w-]{1,64}$", options: .regularExpression) == nil {
            self.controllerNode.showError("Server ID may only contain letters, digits, _ and -")
            return
        }
        if self.inProgress {
            return
        }

        self.inProgress = true
        self.controllerNode.clearError()

        var components = URLComponents(string: "https://server-worker.pages.dev/getserver")
        components?.queryItems = [URLQueryItem(name: "id", value: trimmed)]
        guard let url = components?.url else {
            self.finish(id: trimmed, config: nil, errorMessage: "Invalid server ID")
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10.0
        request.cachePolicy = .reloadIgnoringLocalCacheData

        //fix: the worker answers 4xx with a json body, so parse either way
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            var config: BaigramServerConfig?
            var message: String?

            if let data = data, let object = try? JSONSerialization.jsonObject(with: data), let dict = object as? [String: Any] {
                if dict["code"] as? Int == 0 {
                    let parsed = BaigramServerConfig(
                        id: dict["query"] as? String ?? trimmed,
                        name: dict["name"] as? String ?? "",
                        ip: dict["ip"] as? String ?? "",
                        port: dict["port"] as? Int ?? 0,
                        pubkey: dict["pubkey"] as? String ?? ""
                    )
                    if parsed.isValid {
                        config = parsed
                    } else {
                        message = "Bad response from the server directory"
                    }
                } else {
                    message = dict["msg"] as? String ?? "Server not found"
                }
            } else if let error = error {
                message = error.localizedDescription
            } else {
                message = "Could not reach the server directory"
            }

            DispatchQueue.main.async {
                self?.finish(id: trimmed, config: config, errorMessage: message)
            }
        }.resume()
    }

    private func finish(id: String, config: BaigramServerConfig?, errorMessage: String?) {
        self.inProgress = false

        //fix: known servers must survive an unreachable or distrusted worker
        var resolved = config
        if resolved == nil {
            resolved = BaigramServerConfig.builtin(id: id)
        }

        if let resolved = resolved {
            BaigramServerConfig.apply(resolved, to: self.account.network, accountId: self.account.id)
            self.dismiss()
            self.completed?()
        } else {
            self.controllerNode.showError(errorMessage ?? "Server not found")
        }
    }
}
