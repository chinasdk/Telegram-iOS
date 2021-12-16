import Foundation
import AsyncDisplayKit
import Display
import ComponentFlow
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext
import TelegramPresentationData
import UIKit
import WebPBinding
import AnimatedAvatarSetNode
import ContextUI
import AvatarNode

private final class ReactionImageNode: ASImageNode {
    private var disposable: Disposable?
    let size: CGSize
    
    init(context: AccountContext, availableReactions: AvailableReactions?, reaction: String) {
        var file: TelegramMediaFile?
        if let availableReactions = availableReactions {
            for availableReaction in availableReactions.reactions {
                if availableReaction.value == reaction {
                    file = availableReaction.staticIcon
                    break
                }
            }
        }
        if let file = file {
            self.size = file.dimensions?.cgSize ?? CGSize(width: 18.0, height: 18.0)
            
            super.init()
            
            self.disposable = (context.account.postbox.mediaBox.resourceData(file.resource)
            |> deliverOnMainQueue).start(next: { [weak self] data in
                guard let strongSelf = self else {
                    return
                }
                
                if data.complete, let dataValue = try? Data(contentsOf: URL(fileURLWithPath: data.path)) {
                    if let image = WebP.convert(fromWebP: dataValue) {
                        strongSelf.image = image
                    }
                }
            })
        } else {
            self.size = CGSize(width: 18.0, height: 18.0)
            super.init()
        }
    }
    
    deinit {
        self.disposable?.dispose()
    }
}

private let avatarFont = avatarPlaceholderFont(size: 16.0)

public final class ReactionListContextMenuContent: ContextControllerItemsContent {
    private final class BackButtonNode: HighlightTrackingButtonNode {
        let highlightBackgroundNode: ASDisplayNode
        let titleLabelNode: ImmediateTextNode
        let separatorNode: ASDisplayNode
        let iconNode: ASImageNode
        
        var action: (() -> Void)?
        
        private var theme: PresentationTheme?
        
        init() {
            self.highlightBackgroundNode = ASDisplayNode()
            self.highlightBackgroundNode.alpha = 0.0
            
            self.titleLabelNode = ImmediateTextNode()
            self.titleLabelNode.maximumNumberOfLines = 1
            self.titleLabelNode.isUserInteractionEnabled = false
            
            self.iconNode = ASImageNode()
            
            self.separatorNode = ASDisplayNode()
            
            super.init()
            
            self.addSubnode(self.separatorNode)
            self.addSubnode(self.highlightBackgroundNode)
            self.addSubnode(self.titleLabelNode)
            self.addSubnode(self.iconNode)
            
            self.highligthedChanged = { [weak self] highlighted in
                guard let strongSelf = self else {
                    return
                }
                if highlighted {
                    strongSelf.highlightBackgroundNode.alpha = 1.0
                } else {
                    let previousAlpha = strongSelf.highlightBackgroundNode.alpha
                    strongSelf.highlightBackgroundNode.alpha = 0.0
                    strongSelf.highlightBackgroundNode.layer.animateAlpha(from: previousAlpha, to: 0.0, duration: 0.2)
                }
            }
            
            self.addTarget(self, action: #selector(self.pressed), forControlEvents: .touchUpInside)
        }
        
        @objc private func pressed() {
            self.action?()
        }
        
        func update(size: CGSize, presentationData: PresentationData, isLast: Bool) {
            let standardIconWidth: CGFloat = 32.0
            let sideInset: CGFloat = 16.0
            let iconSideInset: CGFloat = 12.0
            
            if self.theme !== presentationData.theme {
                self.theme = presentationData.theme
                self.iconNode.image = generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Back"), color: presentationData.theme.contextMenu.primaryColor)
            }
            
            self.highlightBackgroundNode.backgroundColor = presentationData.theme.contextMenu.itemHighlightedBackgroundColor
            self.separatorNode.backgroundColor = presentationData.theme.contextMenu.itemSeparatorColor
            
            self.highlightBackgroundNode.frame = CGRect(origin: CGPoint(), size: size)
            
            self.titleLabelNode.attributedText = NSAttributedString(string: presentationData.strings.Common_Back, font: Font.regular(17.0), textColor: presentationData.theme.contextMenu.primaryColor)
            let titleSize = self.titleLabelNode.updateLayout(CGSize(width: size.width - sideInset - standardIconWidth, height: 100.0))
            self.titleLabelNode.frame = CGRect(origin: CGPoint(x: sideInset, y: floor((size.height - titleSize.height) / 2.0)), size: titleSize)
            
            if let iconImage = self.iconNode.image {
                let iconWidth = max(standardIconWidth, iconImage.size.width)
                let iconFrame = CGRect(origin: CGPoint(x: size.width - iconSideInset - iconWidth + floor((iconWidth - iconImage.size.width) / 2.0), y: floor((size.height - iconImage.size.height) / 2.0)), size: iconImage.size)
                self.iconNode.frame = iconFrame
            }
            
            self.separatorNode.frame = CGRect(origin: CGPoint(x: 0.0, y: size.height - UIScreenPixel), size: CGSize(width: size.width, height: UIScreenPixel))
            self.separatorNode.isHidden = isLast
        }
    }
    
    private final class ReactionTabListNode: ASDisplayNode {
        private final class ItemNode: ASDisplayNode {
            let context: AccountContext
            let reaction: String?
            let count: Int
            
            let titleLabelNode: ImmediateTextNode
            let iconNode: ASImageNode?
            let reactionIconNode: ReactionImageNode?
            
            private var theme: PresentationTheme?
            
            var action: ((String?) -> Void)?
            
            init(context: AccountContext, availableReactions: AvailableReactions?, reaction: String?, count: Int) {
                self.context = context
                self.reaction = reaction
                self.count = count
                
                self.titleLabelNode = ImmediateTextNode()
                self.titleLabelNode.isUserInteractionEnabled = false
                
                if let reaction = reaction {
                    self.reactionIconNode = ReactionImageNode(context: context, availableReactions: availableReactions, reaction: reaction)
                    self.reactionIconNode?.isUserInteractionEnabled = false
                    self.iconNode = nil
                } else {
                    self.reactionIconNode = nil
                    self.iconNode = ASImageNode()
                    self.iconNode?.isUserInteractionEnabled = false
                }
                
                super.init()
                
                self.addSubnode(self.titleLabelNode)
                if let iconNode = self.iconNode {
                    self.addSubnode(iconNode)
                }
                if let reactionIconNode = self.reactionIconNode {
                    self.addSubnode(reactionIconNode)
                }
                
                self.view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.tapGesture(_:))))
            }
            
            @objc private func tapGesture(_ recognizer: UITapGestureRecognizer) {
                if case .ended = recognizer.state {
                    self.action?(self.reaction)
                }
            }
            
            func update(presentationData: PresentationData, constrainedSize: CGSize, isSelected: Bool) -> CGSize {
                if presentationData.theme !== self.theme {
                    self.theme = presentationData.theme
                    
                    if let iconNode = self.iconNode {
                        iconNode.image = generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Reactions"), color: presentationData.theme.contextMenu.primaryColor)
                    }
                }
                
                let sideInset: CGFloat = 12.0
                let iconSpacing: CGFloat = 4.0
                
                var iconSize = CGSize(width: 22.0, height: 22.0)
                if let reactionIconNode = self.reactionIconNode {
                    iconSize = reactionIconNode.size.aspectFitted(iconSize)
                } else if let iconNode = self.iconNode, let image = iconNode.image {
                    iconSize = image.size.aspectFitted(iconSize)
                }
                
                self.titleLabelNode.attributedText = NSAttributedString(string: "\(count)", font: Font.medium(11.0), textColor: presentationData.theme.contextMenu.primaryColor)
                let titleSize = self.titleLabelNode.updateLayout(constrainedSize)
                
                let contentSize = CGSize(width: sideInset * 2.0 + titleSize.width + iconSize.width + iconSpacing, height: titleSize.height)
                
                self.titleLabelNode.frame = CGRect(origin: CGPoint(x: sideInset + iconSize.width + iconSpacing, y: floorToScreenPixels((constrainedSize.height - titleSize.height) / 2.0)), size: titleSize)
                
                if let reactionIconNode = self.reactionIconNode {
                    reactionIconNode.frame = CGRect(origin: CGPoint(x: sideInset, y: floorToScreenPixels((constrainedSize.height - iconSize.height) / 2.0)), size: iconSize)
                } else if let iconNode = self.iconNode {
                    iconNode.frame = CGRect(origin: CGPoint(x: sideInset, y: floorToScreenPixels((constrainedSize.height - iconSize.height) / 2.0)), size: iconSize)
                }
                
                return CGSize(width: contentSize.width, height: constrainedSize.height)
            }
        }
        
        private let scrollNode: ASScrollNode
        private let selectionHighlightNode: ASDisplayNode
        private let itemNodes: [ItemNode]
        
        var action: ((String?) -> Void)?
        
        init(context: AccountContext, availableReactions: AvailableReactions?, reactions: [(String?, Int)], message: EngineMessage) {
            self.scrollNode = ASScrollNode()
            self.scrollNode.canCancelAllTouchesInViews = true
            self.scrollNode.view.delaysContentTouches = false
            self.scrollNode.view.showsVerticalScrollIndicator = false
            self.scrollNode.view.showsHorizontalScrollIndicator = false
            if #available(iOS 11.0, *) {
                self.scrollNode.view.contentInsetAdjustmentBehavior = .never
            }
            
            self.itemNodes = reactions.map { reaction, count in
                return ItemNode(context: context, availableReactions: availableReactions, reaction: reaction, count: count)
            }
            
            self.selectionHighlightNode = ASDisplayNode()
            
            super.init()
            
            self.addSubnode(self.scrollNode)
            
            self.scrollNode.addSubnode(self.selectionHighlightNode)
            
            for itemNode in self.itemNodes {
                self.scrollNode.addSubnode(itemNode)
                itemNode.action = { [weak self] reaction in
                    guard let strongSelf = self else {
                        return
                    }
                    strongSelf.action?(reaction)
                }
            }
        }
        
        func update(size: CGSize, presentationData: PresentationData, selectedReaction: String?, transition: ContainedViewLayoutTransition) {
            let sideInset: CGFloat = 11.0
            let spacing: CGFloat = 0.0
            let verticalInset: CGFloat = 7.0
            
            self.selectionHighlightNode.backgroundColor = presentationData.theme.contextMenu.sectionSeparatorColor
            let highlightHeight: CGFloat = size.height - verticalInset * 2.0
            self.selectionHighlightNode.cornerRadius = highlightHeight / 2.0
            
            var contentWidth: CGFloat = sideInset
            for i in 0 ..< self.itemNodes.count {
                if i != 0 {
                    contentWidth += spacing
                }
                
                let itemNode = self.itemNodes[i]
                let itemSize = itemNode.update(presentationData: presentationData, constrainedSize: CGSize(width: size.width, height: size.height), isSelected: itemNode.reaction == selectedReaction)
                let itemFrame = CGRect(origin: CGPoint(x: contentWidth, y: 0.0), size: itemSize)
                itemNode.frame = itemFrame
                
                if itemNode.reaction == selectedReaction {
                    transition.updateFrame(node: self.selectionHighlightNode, frame: CGRect(origin: CGPoint(x: itemFrame.minX, y: verticalInset), size: CGSize(width: itemFrame.width, height: highlightHeight)))
                }
                
                contentWidth += itemSize.width
            }
            contentWidth += sideInset
            
            self.scrollNode.frame = CGRect(origin: CGPoint(), size: size)
            
            let contentSize = CGSize(width: contentWidth, height: size.height)
            if self.scrollNode.view.contentSize != contentSize {
                self.scrollNode.view.contentSize = contentSize
            }
        }
    }
    
    private final class ReactionsTabNode: ASDisplayNode, UIScrollViewDelegate {
        private final class ItemNode: HighlightTrackingButtonNode {
            let context: AccountContext
            let availableReactions: AvailableReactions?
            let highlightBackgroundNode: ASDisplayNode
            let avatarNode: AvatarNode
            let titleLabelNode: ImmediateTextNode
            let separatorNode: ASDisplayNode
            var reactionIconNode: ReactionImageNode?
            let action: () -> Void
            
            init(context: AccountContext, availableReactions: AvailableReactions?, action: @escaping () -> Void) {
                self.action = action
                self.context = context
                self.availableReactions = availableReactions
                self.avatarNode = AvatarNode(font: avatarFont)
                
                self.highlightBackgroundNode = ASDisplayNode()
                self.highlightBackgroundNode.alpha = 0.0
                
                self.titleLabelNode = ImmediateTextNode()
                self.titleLabelNode.maximumNumberOfLines = 1
                self.titleLabelNode.isUserInteractionEnabled = false
                
                self.separatorNode = ASDisplayNode()
                
                super.init()
                
                self.addSubnode(self.separatorNode)
                self.addSubnode(self.highlightBackgroundNode)
                self.addSubnode(self.avatarNode)
                self.addSubnode(self.titleLabelNode)
                
                self.highligthedChanged = { [weak self] highlighted in
                    guard let strongSelf = self else {
                        return
                    }
                    if highlighted {
                        strongSelf.highlightBackgroundNode.alpha = 1.0
                    } else {
                        let previousAlpha = strongSelf.highlightBackgroundNode.alpha
                        strongSelf.highlightBackgroundNode.alpha = 0.0
                        strongSelf.highlightBackgroundNode.layer.animateAlpha(from: previousAlpha, to: 0.0, duration: 0.2)
                    }
                }
                
                self.addTarget(self, action: #selector(self.pressed), forControlEvents: .touchUpInside)
            }
            
            @objc private func pressed() {
                self.action()
            }
            
            func update(size: CGSize, presentationData: PresentationData, item: EngineMessageReactionListContext.Item, isLast: Bool, syncronousLoad: Bool) {
                let avatarInset: CGFloat = 12.0
                let avatarSpacing: CGFloat = 8.0
                let avatarSize: CGFloat = 28.0
                
                let reaction: String? = item.reaction
                if let reaction = reaction {
                    if self.reactionIconNode == nil {
                        let reactionIconNode = ReactionImageNode(context: self.context, availableReactions: self.availableReactions, reaction: reaction)
                        self.reactionIconNode = reactionIconNode
                        self.addSubnode(reactionIconNode)
                    }
                } else if let reactionIconNode = self.reactionIconNode {
                    reactionIconNode.removeFromSupernode()
                }
                
                self.highlightBackgroundNode.backgroundColor = presentationData.theme.contextMenu.itemHighlightedBackgroundColor
                self.separatorNode.backgroundColor = presentationData.theme.contextMenu.itemSeparatorColor
                
                self.highlightBackgroundNode.frame = CGRect(origin: CGPoint(), size: size)
                
                self.avatarNode.frame = CGRect(origin: CGPoint(x: avatarInset, y: floor((size.height - avatarSize) / 2.0)), size: CGSize(width: avatarSize, height: avatarSize))
                self.avatarNode.setPeer(context: self.context, theme: presentationData.theme, peer: item.peer, synchronousLoad: true)
                
                let sideInset: CGFloat = 16.0
                self.titleLabelNode.attributedText = NSAttributedString(string: item.peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder), font: Font.regular(17.0), textColor: presentationData.theme.contextMenu.primaryColor)
                var maxTextWidth: CGFloat = size.width - avatarInset - avatarSize - avatarSpacing - sideInset
                if reactionIconNode != nil {
                    maxTextWidth -= 32.0
                }
                let titleSize = self.titleLabelNode.updateLayout(CGSize(width: maxTextWidth, height: 100.0))
                self.titleLabelNode.frame = CGRect(origin: CGPoint(x: avatarInset + avatarSize + avatarSpacing, y: floor((size.height - titleSize.height) / 2.0)), size: titleSize)
                
                if let reactionIconNode = self.reactionIconNode {
                    let reactionSize = reactionIconNode.size.aspectFitted(CGSize(width: 22.0, height: 22.0))
                    reactionIconNode.frame = CGRect(origin: CGPoint(x: size.width - 32.0 - floor((32.0 - reactionSize.width) / 2.0), y: floor((size.height - reactionSize.height) / 2.0)), size: reactionSize)
                }
                
                self.separatorNode.frame = CGRect(origin: CGPoint(x: 0.0, y: size.height), size: CGSize(width: size.width, height: UIScreenPixel))
                self.separatorNode.isHidden = isLast
            }
        }
        
        private let context: AccountContext
        private let availableReactions: AvailableReactions?
        let reaction: String?
        private let requestUpdate: (ReactionsTabNode, ContainedViewLayoutTransition) -> Void
        private let requestUpdateApparentHeight: (ReactionsTabNode, ContainedViewLayoutTransition) -> Void
        private let openPeer: (PeerId) -> Void
        
        private var hasMore: Bool = false
        
        private let scrollNode: ASScrollNode
        private var ignoreScrolling: Bool = false
        
        private var presentationData: PresentationData?
        private var currentSize: CGSize?
        private var apparentHeight: CGFloat = 0.0
        
        private let listContext: EngineMessageReactionListContext
        private var state: EngineMessageReactionListContext.State
        private var stateDisposable: Disposable?
        
        private var itemNodes: [Int: ItemNode] = [:]
        
        init(
            context: AccountContext,
            availableReactions: AvailableReactions?,
            message: EngineMessage,
            reaction: String?,
            requestUpdate: @escaping (ReactionsTabNode, ContainedViewLayoutTransition) -> Void,
            requestUpdateApparentHeight: @escaping (ReactionsTabNode, ContainedViewLayoutTransition) -> Void,
            openPeer: @escaping (PeerId) -> Void
        ) {
            self.context = context
            self.availableReactions = availableReactions
            self.reaction = reaction
            self.requestUpdate = requestUpdate
            self.requestUpdateApparentHeight = requestUpdateApparentHeight
            self.openPeer = openPeer
            
            self.presentationData = context.sharedContext.currentPresentationData.with({ $0 })
            self.listContext = context.engine.messages.messageReactionList(message: message, reaction: reaction)
            self.state = EngineMessageReactionListContext.State(message: message, reaction: reaction)
            
            self.scrollNode = ASScrollNode()
            self.scrollNode.canCancelAllTouchesInViews = true
            self.scrollNode.view.delaysContentTouches = false
            self.scrollNode.view.showsVerticalScrollIndicator = false
            if #available(iOS 11.0, *) {
                self.scrollNode.view.contentInsetAdjustmentBehavior = .never
            }
            self.scrollNode.clipsToBounds = false
            
            super.init()
            
            self.addSubnode(self.scrollNode)
            self.scrollNode.view.delegate = self
            
            self.clipsToBounds = true
            
            self.stateDisposable = (self.listContext.state
            |> deliverOnMainQueue).start(next: { [weak self] state in
                guard let strongSelf = self else {
                    return
                }
                var animateIn = false
                if strongSelf.state.items.isEmpty && !state.items.isEmpty {
                    animateIn = true
                }
                strongSelf.state = state
                strongSelf.requestUpdate(strongSelf, .immediate)
                if animateIn {
                    strongSelf.scrollNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
                }
            })
        }
        
        deinit {
            self.stateDisposable?.dispose()
        }
        
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            if self.ignoreScrolling {
                return
            }
            self.updateVisibleItems(syncronousLoad: false)
            
            if let size = self.currentSize {
                var apparentHeight = -self.scrollNode.view.contentOffset.y + self.scrollNode.view.contentSize.height
                apparentHeight = max(apparentHeight, 44.0)
                apparentHeight = min(apparentHeight, size.height + 100.0)
                if self.apparentHeight != apparentHeight {
                    self.apparentHeight = apparentHeight
                    
                    self.requestUpdateApparentHeight(self, .immediate)
                }
            }
        }
        
        private func updateVisibleItems(syncronousLoad: Bool) {
            guard let size = self.currentSize else {
                return
            }
            guard let presentationData = self.presentationData else {
                return
            }
            let itemHeight: CGFloat = 44.0
            let visibleBounds = self.scrollNode.bounds.insetBy(dx: 0.0, dy: -180.0)
            
            var validIds = Set<Int>()
            
            let minVisibleIndex = max(0, Int(floor(visibleBounds.minY / itemHeight)))
            let maxVisibleIndex = Int(ceil(visibleBounds.maxY / itemHeight))
            
            if minVisibleIndex <= maxVisibleIndex {
                for index in minVisibleIndex ... maxVisibleIndex {
                    if index >= self.state.items.count {
                        break
                    }
                    
                    validIds.insert(index)
                    
                    let itemNode: ItemNode
                    if let current = self.itemNodes[index] {
                        itemNode = current
                    } else {
                        let openPeer = self.openPeer
                        let peerId = self.state.items[index].peer.id
                        itemNode = ItemNode(context: self.context, availableReactions: self.availableReactions, action: {
                            openPeer(peerId)
                        })
                        self.itemNodes[index] = itemNode
                        self.scrollNode.addSubnode(itemNode)
                    }
                    
                    let itemFrame = CGRect(origin: CGPoint(x: 0.0, y: CGFloat(index) * itemHeight), size: CGSize(width: size.width, height: itemHeight))
                    itemNode.update(size: itemFrame.size, presentationData: presentationData, item: self.state.items[index], isLast: index == self.state.items.count - 1, syncronousLoad: syncronousLoad)
                    itemNode.frame = itemFrame
                }
            }
            
            var removeIds: [Int] = []
            for (id, itemNode) in self.itemNodes {
                if !validIds.contains(id) {
                    removeIds.append(id)
                    itemNode.removeFromSupernode()
                }
            }
            
            for id in removeIds {
                self.itemNodes.removeValue(forKey: id)
            }
            
            if self.state.canLoadMore && maxVisibleIndex >= self.state.items.count - 16 {
                self.listContext.loadMore()
            }
        }
        
        func update(constrainedSize: CGSize, transition: ContainedViewLayoutTransition) -> (size: CGSize, apparentHeight: CGFloat) {
            let itemHeight: CGFloat = 44.0
            let size = CGSize(width: constrainedSize.width, height: CGFloat(self.state.totalCount) * itemHeight)
            
            let containerSize = CGSize(width: size.width, height: min(constrainedSize.height, size.height))
            self.currentSize = containerSize
            
            self.ignoreScrolling = true
            
            if self.scrollNode.frame != CGRect(origin: CGPoint(), size: containerSize) {
                self.scrollNode.frame = CGRect(origin: CGPoint(), size: containerSize)
            }
            if self.scrollNode.view.contentSize != size {
                self.scrollNode.view.contentSize = size
            }
            self.ignoreScrolling = false
            
            self.updateVisibleItems(syncronousLoad: !transition.isAnimated)
            
            var apparentHeight = -self.scrollNode.view.contentOffset.y + self.scrollNode.view.contentSize.height
            apparentHeight = max(apparentHeight, 44.0)
            apparentHeight = min(apparentHeight, containerSize.height + 100.0)
            self.apparentHeight = apparentHeight
            
            return (containerSize, apparentHeight)
        }
    }
    
    final class ItemsNode: ASDisplayNode, ContextControllerItemsNode {
        private let context: AccountContext
        private let availableReactions: AvailableReactions?
        private let reactions: [(String?, Int)]
        private let requestUpdate: (ContainedViewLayoutTransition) -> Void
        private let requestUpdateApparentHeight: (ContainedViewLayoutTransition) -> Void
        
        private var presentationData: PresentationData
        
        private var backButtonNode: BackButtonNode?
        private var separatorNode: ASDisplayNode?
        private var tabListNode: ReactionTabListNode?
        private var currentTabNode: ReactionsTabNode
        
        private var dismissedTabNode: ReactionsTabNode?
        
        private let openPeer: (PeerId) -> Void
        
        private(set) var apparentHeight: CGFloat = 0.0
        
        init(
            context: AccountContext,
            availableReactions: AvailableReactions?,
            message: EngineMessage,
            requestUpdate: @escaping (ContainedViewLayoutTransition) -> Void,
            requestUpdateApparentHeight: @escaping (ContainedViewLayoutTransition) -> Void,
            back: @escaping () -> Void,
            openPeer: @escaping (PeerId) -> Void
        ) {
            self.context = context
            self.availableReactions = availableReactions
            self.openPeer = openPeer
            self.presentationData = context.sharedContext.currentPresentationData.with({ $0 })
            
            self.requestUpdate = requestUpdate
            self.requestUpdateApparentHeight = requestUpdateApparentHeight
            
            var requestUpdateTab: ((ReactionsTabNode, ContainedViewLayoutTransition) -> Void)?
            var requestUpdateTabApparentHeight: ((ReactionsTabNode, ContainedViewLayoutTransition) -> Void)?
            
            self.backButtonNode = BackButtonNode()
            self.backButtonNode?.action = {
                back()
            }
            
            var reactions: [(String?, Int)] = []
            var totalCount: Int = 0
            if let reactionsAttribute = message._asMessage().reactionsAttribute {
                for reaction in reactionsAttribute.reactions {
                    totalCount += Int(reaction.count)
                    reactions.append((reaction.value, Int(reaction.count)))
                }
            }
            reactions.insert((nil, totalCount), at: 0)
            
            if reactions.count > 2 {
                self.tabListNode = ReactionTabListNode(context: context, availableReactions: availableReactions, reactions: reactions, message: message)
            }
            
            self.reactions = reactions
            
            self.separatorNode = ASDisplayNode()
            
            self.currentTabNode = ReactionsTabNode(
                context: context,
                availableReactions: availableReactions,
                message: message,
                reaction: nil,
                requestUpdate: { tab, transition in
                    requestUpdateTab?(tab, transition)
                },
                requestUpdateApparentHeight: { tab, transition in
                    requestUpdateTabApparentHeight?(tab, transition)
                },
                openPeer: { id in
                    openPeer(id)
                }
            )
            
            super.init()
            
            if let backButtonNode = self.backButtonNode {
                self.addSubnode(backButtonNode)
            }
            if let tabListNode = self.tabListNode {
                self.addSubnode(tabListNode)
            }
            if let separatorNode = self.separatorNode {
                self.addSubnode(separatorNode)
            }
            self.addSubnode(self.currentTabNode)
            
            self.tabListNode?.action = { [weak self] reaction in
                guard let strongSelf = self else {
                    return
                }
                if strongSelf.currentTabNode.reaction != reaction {
                    strongSelf.dismissedTabNode = strongSelf.currentTabNode
                    let currentTabNode = ReactionsTabNode(
                        context: context,
                        availableReactions: availableReactions,
                        message: message,
                        reaction: reaction,
                        requestUpdate: { tab, transition in
                            requestUpdateTab?(tab, transition)
                        },
                        requestUpdateApparentHeight: { tab, transition in
                            requestUpdateTabApparentHeight?(tab, transition)
                        },
                        openPeer: { id in
                            openPeer(id)
                        }
                    )
                    strongSelf.currentTabNode = currentTabNode
                    strongSelf.addSubnode(currentTabNode)
                    strongSelf.requestUpdate(.animated(duration: 0.45, curve: .spring))
                }
            }
            
            requestUpdateTab = { [weak self] tab, transition in
                guard let strongSelf = self else {
                    return
                }
                if strongSelf.currentTabNode == tab {
                    strongSelf.requestUpdate(transition)
                }
            }
            
            requestUpdateTabApparentHeight = { [weak self] tab, transition in
                guard let strongSelf = self else {
                    return
                }
                if strongSelf.currentTabNode == tab {
                    strongSelf.requestUpdateApparentHeight(transition)
                }
            }
        }
        
        func update(constrainedWidth: CGFloat, maxHeight: CGFloat, bottomInset: CGFloat, transition: ContainedViewLayoutTransition) -> (cleanSize: CGSize, apparentHeight: CGFloat) {
            let constrainedSize = CGSize(width: min(260.0, constrainedWidth), height: maxHeight)
            
            var topContentHeight: CGFloat = 0.0
            if let backButtonNode = self.backButtonNode {
                let backButtonFrame = CGRect(origin: CGPoint(x: 0.0, y: topContentHeight), size: CGSize(width: constrainedSize.width, height: 45.0))
                backButtonNode.update(size: backButtonFrame.size, presentationData: self.presentationData, isLast: self.tabListNode == nil)
                transition.updateFrame(node: backButtonNode, frame: backButtonFrame)
                topContentHeight += backButtonFrame.height
            }
            if let tabListNode = self.tabListNode {
                let tabListFrame = CGRect(origin: CGPoint(x: 0.0, y: topContentHeight), size: CGSize(width: constrainedSize.width, height: 44.0))
                tabListNode.update(size: tabListFrame.size, presentationData: self.presentationData, selectedReaction: self.currentTabNode.reaction, transition: transition)
                transition.updateFrame(node: tabListNode, frame: tabListFrame)
                topContentHeight += tabListFrame.height
            }
            if let separatorNode = self.separatorNode {
                let separatorFrame = CGRect(origin: CGPoint(x: 0.0, y: topContentHeight), size: CGSize(width: constrainedSize.width, height: 7.0))
                separatorNode.backgroundColor = self.presentationData.theme.contextMenu.sectionSeparatorColor
                transition.updateFrame(node: separatorNode, frame: separatorFrame)
                topContentHeight += separatorFrame.height
            }
            
            var currentTabTransition = transition
            if self.currentTabNode.bounds.isEmpty {
                currentTabTransition = .immediate
            }
            let currentTabLayout = self.currentTabNode.update(constrainedSize: CGSize(width: constrainedSize.width, height: constrainedSize.height - topContentHeight), transition: currentTabTransition)
            currentTabTransition.updateFrame(node: self.currentTabNode, frame: CGRect(origin: CGPoint(x: 0.0, y: topContentHeight), size: CGSize(width: currentTabLayout.size.width, height: currentTabLayout.size.height + 100.0)))
            
            if let dismissedTabNode = self.dismissedTabNode {
                self.dismissedTabNode = nil
                if let previousIndex = self.reactions.firstIndex(where: { $0.0 == dismissedTabNode.reaction }), let currentIndex = self.reactions.firstIndex(where: { $0.0 == self.currentTabNode.reaction }) {
                    let offset = previousIndex < currentIndex ? currentTabLayout.size.width : -currentTabLayout.size.width
                    transition.updateFrame(node: dismissedTabNode, frame: dismissedTabNode.frame.offsetBy(dx: -offset, dy: 0.0), completion: { [weak dismissedTabNode] _ in
                        dismissedTabNode?.removeFromSupernode()
                    })
                    transition.animatePositionAdditive(node: self.currentTabNode, offset: CGPoint(x: offset, y: 0.0))
                } else {
                    dismissedTabNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false, completion: { [weak dismissedTabNode] _ in
                        dismissedTabNode?.removeFromSupernode()
                    })
                    self.currentTabNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
                }
            }
            
            let contentSize = CGSize(width: currentTabLayout.size.width, height: topContentHeight + currentTabLayout.size.height)
            
            let apparentHeight = topContentHeight + currentTabLayout.apparentHeight
            
            return (contentSize, apparentHeight)
        }
    }
    
    let context: AccountContext
    let availableReactions: AvailableReactions?
    let message: EngineMessage
    let back: () -> Void
    let openPeer: (PeerId) -> Void
    
    public init(context: AccountContext, availableReactions: AvailableReactions?, message: EngineMessage, back: @escaping () -> Void, openPeer: @escaping (PeerId) -> Void) {
        self.context = context
        self.availableReactions = availableReactions
        self.message = message
        self.back = back
        self.openPeer = openPeer
    }
    
    public func node(
        requestUpdate: @escaping (ContainedViewLayoutTransition) -> Void,
        requestUpdateApparentHeight: @escaping (ContainedViewLayoutTransition) -> Void
    ) -> ContextControllerItemsNode {
        return ItemsNode(
            context: self.context,
            availableReactions: self.availableReactions,
            message: self.message,
            requestUpdate: requestUpdate,
            requestUpdateApparentHeight: requestUpdateApparentHeight,
            back: self.back,
            openPeer: self.openPeer
        )
    }
}
