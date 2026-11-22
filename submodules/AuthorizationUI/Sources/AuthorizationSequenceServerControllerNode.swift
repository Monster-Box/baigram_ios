import Foundation
import UIKit
import AsyncDisplayKit
import Display
import TelegramPresentationData
import AuthorizationUtils
import SolidRoundedButtonNode

final class AuthorizationSequenceServerControllerNode: ASDisplayNode, UITextFieldDelegate {
    private let theme: PresentationTheme

    private let titleNode: ASTextNode
    private let noticeNode: ASTextNode
    private let fieldNode: TextFieldNode
    private let separatorNode: ASDisplayNode
    private let errorNode: ASTextNode
    private let proceedNode: SolidRoundedButtonNode

    private var layoutArguments: (ContainerViewLayout, CGFloat)?

    var currentServerId: String {
        return self.fieldNode.textField.text ?? ""
    }

    var proceed: ((String) -> Void)?

    var inProgress: Bool = false {
        didSet {
            self.fieldNode.alpha = self.inProgress ? 0.6 : 1.0

            if self.inProgress != oldValue {
                if self.inProgress {
                    self.proceedNode.transitionToProgress()
                } else {
                    self.proceedNode.transitionFromProgress()
                }
            }
        }
    }

    init(strings: PresentationStrings, theme: PresentationTheme, currentServerId: String) {
        self.theme = theme

        self.titleNode = ASTextNode()
        self.titleNode.isUserInteractionEnabled = false
        self.titleNode.displaysAsynchronously = false

        self.noticeNode = ASTextNode()
        self.noticeNode.isUserInteractionEnabled = false
        self.noticeNode.displaysAsynchronously = false
        self.noticeNode.lineSpacing = 0.1
        self.noticeNode.attributedText = NSAttributedString(string: "Enter the ID of the server you want to connect to.", font: Font.regular(16.0), textColor: theme.list.itemPrimaryTextColor)

        self.fieldNode = TextFieldNode()
        self.fieldNode.textField.font = Font.regular(20.0)
        self.fieldNode.textField.textColor = theme.list.itemPrimaryTextColor
        self.fieldNode.textField.textAlignment = .natural
        self.fieldNode.textField.autocorrectionType = .no
        self.fieldNode.textField.autocapitalizationType = .none
        self.fieldNode.textField.keyboardType = .asciiCapable
        self.fieldNode.textField.returnKeyType = .done
        self.fieldNode.textField.keyboardAppearance = theme.rootController.keyboardColor.keyboardAppearance
        self.fieldNode.textField.disableAutomaticKeyboardHandling = [.forward, .backward]
        self.fieldNode.textField.tintColor = theme.list.itemAccentColor
        self.fieldNode.textField.placeholder = "Server ID"
        self.fieldNode.textField.text = currentServerId

        self.separatorNode = ASDisplayNode()
        self.separatorNode.isLayerBacked = true
        self.separatorNode.backgroundColor = theme.list.itemPlainSeparatorColor

        self.errorNode = ASTextNode()
        self.errorNode.isUserInteractionEnabled = false
        self.errorNode.displaysAsynchronously = false
        self.errorNode.alpha = 0.0

        self.proceedNode = SolidRoundedButtonNode(title: "Continue", theme: SolidRoundedButtonTheme(theme: theme), glass: false, height: 50.0, cornerRadius: 50.0 * 0.5)
        self.proceedNode.progressType = .embedded

        super.init()

        self.backgroundColor = theme.list.plainBackgroundColor

        self.fieldNode.textField.delegate = self

        self.addSubnode(self.titleNode)
        self.addSubnode(self.noticeNode)
        self.addSubnode(self.fieldNode)
        self.addSubnode(self.separatorNode)
        self.addSubnode(self.errorNode)
        self.addSubnode(self.proceedNode)

        self.fieldNode.textField.addTarget(self, action: #selector(self.textDidChange), for: .editingChanged)
        self.proceedNode.pressed = { [weak self] in
            self?.proceedPressed()
        }
    }

    @objc private func textDidChange() {
        self.clearError()
    }

    func updateTitle(_ title: String) {
        self.titleNode.attributedText = NSAttributedString(string: title, font: Font.bold(28.0), textColor: self.theme.list.itemPrimaryTextColor)
    }

    func showError(_ text: String) {
        self.errorNode.attributedText = NSAttributedString(string: text, font: Font.regular(14.0), textColor: self.theme.list.itemDestructiveColor)
        self.errorNode.alpha = 1.0
        self.fieldNode.layer.addShakeAnimation()
    }

    func clearError() {
        if self.errorNode.alpha != 0.0 {
            self.errorNode.alpha = 0.0
            self.errorNode.attributedText = nil
        }
    }

    func containerLayoutUpdated(_ layout: ContainerViewLayout, navigationBarHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        self.layoutArguments = (layout, navigationBarHeight)

        var insets = layout.insets(options: [])
        insets.top = navigationBarHeight
        if let inputHeight = layout.inputHeight {
            insets.bottom = max(inputHeight, insets.bottom)
        }

        let (bandMinX, bandWidth) = authorizationContentBand(layout: layout)
        let (bottomBandMinX, bottomBandWidth) = authorizationBottomBand(layout: layout)
        let maximumWidth: CGFloat = min(430.0, bandWidth)
        let bottomMaximumWidth: CGFloat = min(430.0, bottomBandWidth)
        let inset: CGFloat = 24.0

        self.titleNode.attributedText = NSAttributedString(string: "Server", font: Font.bold(28.0), textColor: self.theme.list.itemPrimaryTextColor)
        let titleSize = self.titleNode.measure(CGSize(width: maximumWidth - 48.0, height: CGFloat.greatestFiniteMagnitude))
        let noticeSize = self.noticeNode.measure(CGSize(width: maximumWidth - 48.0, height: CGFloat.greatestFiniteMagnitude))
        let fieldWidth = maximumWidth - 48.0
        let errorSize = self.errorNode.measure(CGSize(width: fieldWidth, height: CGFloat.greatestFiniteMagnitude))

        let contentWidth: CGFloat = maximumWidth - 48.0
        let contentX = bandMinX + floorToScreenPixels((bandWidth - contentWidth) / 2.0)

        var y = insets.top + 18.0
        transition.updateFrame(node: self.titleNode, frame: CGRect(origin: CGPoint(x: contentX, y: y), size: CGSize(width: contentWidth, height: titleSize.height)))
        y += titleSize.height + 8.0
        transition.updateFrame(node: self.noticeNode, frame: CGRect(origin: CGPoint(x: contentX, y: y), size: CGSize(width: contentWidth, height: noticeSize.height)))
        y += noticeSize.height + 24.0
        transition.updateFrame(node: self.fieldNode, frame: CGRect(origin: CGPoint(x: contentX + 12.0, y: y), size: CGSize(width: contentWidth - 24.0, height: 44.0)))
        y += 44.0
        transition.updateFrame(node: self.separatorNode, frame: CGRect(origin: CGPoint(x: contentX, y: y), size: CGSize(width: contentWidth, height: UIScreenPixel)))
        y += 8.0
        transition.updateFrame(node: self.errorNode, frame: CGRect(origin: CGPoint(x: contentX, y: y), size: CGSize(width: contentWidth, height: errorSize.height)))

        let proceedHeight = self.proceedNode.updateLayout(width: bottomMaximumWidth - 48.0, transition: transition)
        transition.updateFrame(node: self.proceedNode, frame: CGRect(origin: CGPoint(x: bottomBandMinX + floorToScreenPixels((bottomBandWidth - (bottomMaximumWidth - 48.0)) / 2.0), y: layout.size.height - insets.bottom - proceedHeight - inset), size: CGSize(width: bottomMaximumWidth - 48.0, height: proceedHeight)))
    }

    func activateInput() {
        self.fieldNode.textField.becomeFirstResponder()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        self.proceed?(self.currentServerId)
        return false
    }

    @objc func proceedPressed() {
        self.proceed?(self.currentServerId)
    }
}
