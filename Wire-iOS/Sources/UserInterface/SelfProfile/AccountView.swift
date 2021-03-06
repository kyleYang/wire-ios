//
// Wire
// Copyright (C) 2017 Wire Swiss GmbH
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see http://www.gnu.org/licenses/.
//

import UIKit
import Cartography
import Classy


open class LayerHostView<LayerType: CALayer>: UIView {
    var hostedLayer: LayerType {
        return self.layer as! LayerType
    }
    override open class var layerClass : AnyClass {
        return LayerType.self
    }
}


class ShapeView: LayerHostView<CAShapeLayer> {
    public var pathGenerator: ((CGSize) -> (UIBezierPath))? {
        didSet {
            self.updatePath()
        }
    }

    private var lastBounds: CGRect = .zero
    
    private func updatePath() {
        guard let generator = self.pathGenerator else {
            return
        }
        
        self.hostedLayer.path = generator(bounds.size).cgPath
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        if lastBounds != self.bounds {
           lastBounds = self.bounds
            
            self.updatePath()
        }
    }
}

class DotView: UIView {
    fileprivate let circleView = ShapeView()
    fileprivate let centerView = ShapeView()
    private var userObserver: NSObjectProtocol!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        circleView.pathGenerator = {
            return UIBezierPath(ovalIn: CGRect(origin: .zero, size: $0))
        }
        circleView.hostedLayer.lineWidth = 0
        circleView.hostedLayer.fillColor = UIColor.white.cgColor
        
        centerView.pathGenerator = {
            return UIBezierPath(ovalIn: CGRect(origin: .zero, size: $0).insetBy(dx: 1, dy: 1))
        }
        centerView.hostedLayer.fillColor = UIColor.accent().cgColor
        
        addSubview(circleView)
        addSubview(centerView)
        constrain(self, circleView, centerView) { selfView, backingView, centerView in
            backingView.edges == selfView.edges
            centerView.edges == selfView.edges
        }
        
        if let selfUser = ZMUser.selfUser() {
            userObserver = UserChangeInfo.add(observer: self, forBareUser: selfUser)
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension DotView: ZMUserObserver {
    func userDidChange(_ changeInfo: UserChangeInfo) {
        guard changeInfo.accentColorValueChanged && changeInfo.user.isSelfUser else {
            return
        }
        
        centerView.hostedLayer.fillColor = UIColor.accent().cgColor
    }
}

public protocol AccountViewType {
    var collapsed: Bool { get set }
    var hasUnreadMessages: Bool { get }
    var onTap: ((Account?) -> ())? { get set }
    func update()
    var account: Account { get }
}

public final class AccountViewFactory {
    public static func viewFor(account: Account) -> BaseAccountView {
        return account.teamName == nil ? PersonalAccountView(account: account) : TeamAccountView(account: account)
    }
}

public class BaseAccountView: UIView, AccountViewType {
    
    internal let imageViewContainer = UIView()
    fileprivate let outlineView = UIView()
    fileprivate let dotView = DotView()
    fileprivate let selectionView = ShapeView()
    
    private var selfUserObserver: NSObjectProtocol!

    public var selected: Bool = false {
        didSet {
            updateAppearance()
        }
    }
    
    public var collapsed: Bool = false {
        didSet {
            updateAppearance()
        }
    }
    
    public var hasUnreadMessages: Bool {
        return false
    }
    
    public let account: Account
    
    func updateAppearance() {
        selectionView.isHidden = !selected || collapsed
        dotView.isHidden = selected || !hasUnreadMessages || collapsed
        
        selectionView.hostedLayer.strokeColor = UIColor.accent().cgColor
    }
    
    public var onTap: ((Account?) -> ())? = .none
    
    public var accessibilityState: String {
        return ("conversation_list.header.self_team.accessibility_value." + (self.selected ? "active" : "inactive")).localized +
                (self.hasUnreadMessages ? (" " + "conversation_list.header.self_team.accessibility_value.has_new_messages".localized) : "")
    }
    
    init(account: Account) {
        self.account = account
        super.init(frame: .zero)
        
        selfUserObserver = UserChangeInfo.add(observer: self, forBareUser: ZMUser.selfUser())

        selectionView.hostedLayer.strokeColor = UIColor.accent().cgColor
        selectionView.hostedLayer.fillColor = UIColor.clear.cgColor
        selectionView.hostedLayer.lineWidth = 1.5
        selectionView.layoutMargins = UIEdgeInsets(top: 1, left: 1, bottom: 1, right: 1)
        
        [imageViewContainer, outlineView, selectionView, dotView].forEach(self.addSubview)
        
        constrain(imageViewContainer, selectionView) { imageViewContainer, selectionView in
            selectionView.edgesWithinMargins == imageViewContainer.edges
        }

        let dotSize: CGFloat = 9

        constrain(imageViewContainer, dotView) { imageViewContainer, dotView in
            dotView.centerX == imageViewContainer.trailing - 3
            dotView.centerY == imageViewContainer.centerY - 6
            
            dotView.width == dotView.height
            dotView.height == dotSize
        }
        
        constrain(self, imageViewContainer, dotView) { selfView, imageViewContainer, dotView in
            imageViewContainer.top == selfView.top + 12
            imageViewContainer.centerX == selfView.centerX
            selfView.width >= imageViewContainer.width
            selfView.trailing >= dotView.trailing
            
            imageViewContainer.width == 33
            imageViewContainer.height == imageViewContainer.width
            
            imageViewContainer.bottom == selfView.bottom - 4
            imageViewContainer.leading == selfView.leading + 7
            imageViewContainer.trailing == selfView.trailing - 7
            selfView.width <= 128
        }
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTap(_:)))
        self.addGestureRecognizer(tapGesture)
        
        updateAppearance()
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func update() {
        self.selected = SessionManager.shared?.accountManager.selectedAccount == self.account
    }
    
    @objc public func didTap(_ sender: UITapGestureRecognizer!) {
        self.onTap?(self.account)
    }
}

extension BaseAccountView: ZMConversationListObserver {
    public func conversationListDidChange(_ changeInfo: ConversationListChangeInfo) {
        updateAppearance()
    }
    
    public func conversationInsideList(_ list: ZMConversationList, didChange changeInfo: ConversationChangeInfo) {
        updateAppearance()
    }
}

extension BaseAccountView: ZMUserObserver {
    public func userDidChange(_ changeInfo: UserChangeInfo) {
        if changeInfo.accentColorValueChanged {
            updateAppearance()
        }
    }
}

public final class PersonalAccountView: BaseAccountView {
    internal let userImageView = AvatarImageView(frame: .zero)

    private var conversationListObserver: NSObjectProtocol!
    private var connectionRequestObserver: NSObjectProtocol!
    
    public override var collapsed: Bool {
        didSet {
            self.userImageView.isHidden = collapsed
        }
    }
    
    override init(account: Account) {
        super.init(account: account)
        
        self.isAccessibilityElement = true
        self.accessibilityTraits = UIAccessibilityTraitButton
        self.shouldGroupAccessibilityChildren = true
        self.accessibilityIdentifier = "personal team"

        if let imageData = self.account.imageData {
            userImageView.imageView.image = UIImage(data: imageData)
        }
        else {
            let personName = PersonName.person(withName: self.account.userName, schemeTagger: nil)
            userImageView.initials.text = personName.initials
        }
        
        selectionView.pathGenerator = {
            return UIBezierPath(ovalIn: CGRect(origin: .zero, size: $0))
        }

        if let userSession = ZMUserSession.shared() {
            conversationListObserver = ConversationListChangeInfo.add(observer: self, for: ZMConversationList.conversations(inUserSession: userSession))
            connectionRequestObserver = ConversationListChangeInfo.add(observer: self, for: ZMConversationList.pendingConnectionConversations(inUserSession: userSession))
        }
        
        self.imageViewContainer.addSubview(userImageView)
        self.imageViewContainer.layoutMargins = UIEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)
        constrain(imageViewContainer, userImageView) { imageViewContainer, userImageView in
            userImageView.edges == imageViewContainer.edgesWithinMargins
        }
        
        update()
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func update() {
        super.update()
        self.accessibilityValue = String(format: "conversation_list.header.self_team.accessibility_value".localized, self.account.userName) + " " + accessibilityState
    }
}

extension PersonalAccountView {
    override public func userDidChange(_ changeInfo: UserChangeInfo) {
        super.userDidChange(changeInfo)
        if changeInfo.nameChanged {
            update()
        }
    }
}

public final class TeamImageView: UIImageView {
    public enum TeamImageViewStyle {
        case small
        case big
    }
    
    private let account: Account
    
    private var lastLayoutBounds: CGRect = .zero
    private let maskLayer = CALayer()
    internal let initialLabel = UILabel()
    public var style: TeamImageViewStyle = .small {
        didSet {
            switch (self.style) {
            case .big:
                self.cas_styleClass = "big"
            case .small:
                self.cas_styleClass = nil
            }
        }
    }
    
    init(account: Account) {
        self.account = account
        super.init(frame: .zero)
        layer.mask = maskLayer
        
        initialLabel.textAlignment = .center
        self.addSubview(self.initialLabel)
        self.accessibilityElements = [initialLabel]
        
        constrain(self, initialLabel) { selfView, initialLabel in
            initialLabel.centerY == selfView.centerY
            initialLabel.centerX == selfView.centerX
        }
        
        maskLayer.contentsScale = UIScreen.main.scale
        maskLayer.contentsGravity = "center"
        self.updateClippingLayer()
        self.updateImage()
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func updateClippingLayer() {
        guard bounds.size != .zero else {
            return
        }
        
        UIGraphicsBeginImageContextWithOptions(bounds.size, false, maskLayer.contentsScale)
        WireStyleKit.drawSpace(withFrame: bounds, resizing: WireStyleKitResizingBehaviorAspectFit, color: .black)
        
        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        
        maskLayer.frame = layer.bounds
        maskLayer.contents = image.cgImage
    }
    
    override public func layoutSubviews() {
        super.layoutSubviews()
        
        if !bounds.equalTo(lastLayoutBounds) {
            updateClippingLayer()
            lastLayoutBounds = self.bounds
        }
    }
    
    fileprivate func updateImage() {
        if let imageData = self.account.imageData {
            self.image = UIImage(data: imageData)
            self.initialLabel.text = ""
        }
        else if let name = self.account.teamName {
            self.image = nil
            self.initialLabel.text = name.substring(to: name.index(after: name.startIndex))
        }
    }
}

@objc internal class TeamAccountView: BaseAccountView {

    public override var collapsed: Bool {
        didSet {
            self.imageView.isHidden = collapsed
        }
    }
    
    
    private let imageView: TeamImageView
    
    private var teamObserver: NSObjectProtocol!
    private var conversationListObserver: NSObjectProtocol!

    override init(account: Account) {
        
        imageView = TeamImageView(account: account)
        
        super.init(account: account)
        
        isAccessibilityElement = true
        accessibilityTraits = UIAccessibilityTraitButton
        shouldGroupAccessibilityChildren = true
        
        imageView.contentMode = .scaleAspectFill
        
        imageViewContainer.addSubview(imageView)
        
        self.selectionView.pathGenerator = { size in
            
            let path = WireStyleKit.pathForTeamSelection()!
            let scale = (size.width - 1) / path.bounds.width
            path.apply(CGAffineTransform(scaleX: scale, y: scale))
            return path
        }
        
        self.imageViewContainer.layoutMargins = UIEdgeInsets(top: 1, left: 1, bottom: 1, right: 1)
        constrain(imageViewContainer, imageView) { imageViewContainer, imageView in
            imageView.edges == imageViewContainer.edgesWithinMargins
        }

        update()
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTap(_:)))
        addGestureRecognizer(tapGesture)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func update() {
        super.update()
        imageView.updateImage()
        accessibilityValue = String(format: "conversation_list.header.self_team.accessibility_value".localized, self.account.teamName ?? "") + " " + accessibilityState
        accessibilityIdentifier = "\(self.account.teamName ?? "") team"
    }
    
    
    static let ciContext: CIContext = {
        return CIContext()
    }()
}

extension TeamAccountView: TeamObserver {
    func teamDidChange(_ changeInfo: TeamChangeInfo) {
        self.update()
    }
}
