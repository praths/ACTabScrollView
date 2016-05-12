//
//  ACTabScrollView.swift
//  ACTabScrollView
//
//  Created by AzureChen on 2015/8/19.
//  Copyright (c) 2015 AzureChen. All rights reserved.
//

//  TODO:
//   1. Performace improvement
//   2. Adjust the scrolling offset if tabs have diffent widths
//   3. Test reloadData function
//   4. Init with frame
//   5. Flexiable tab height
//   6. Tabs in the bottom

import UIKit

@IBDesignable
public class ACTabScrollView: UIView, UIScrollViewDelegate {
    
    // MARK: Public Variables
    @IBInspectable public var tabGradient: Bool = true
    @IBInspectable public var tabSectionBackgroundColor: UIColor = UIColor.whiteColor()
    @IBInspectable public var contentSectionBackgroundColor: UIColor = UIColor.whiteColor()
    @IBInspectable public var cachePageLimit: Int = 3
    @IBInspectable public var pagingEnabled: Bool = true {
        didSet {
            contentSectionScrollView.pagingEnabled = pagingEnabled
        }
    }
    @IBInspectable public var defaultPage: Int = 0
    @IBInspectable public var defaultTabHeight: CGFloat = 30
    
    public var delegate: ACTabScrollViewDelegate?
    public var dataSource: ACTabScrollViewDataSource?
    
    // MARK: Private Variables
    private var tabSectionScrollView: UIScrollView!
    private var contentSectionScrollView: UIScrollView!
    private var cachedPageTabs: [Int: UIView] = [:]
    private var cachedPageContents: CacheQueue<Int, UIView> = CacheQueue()
    private var realCachePageLimit: Int {
        var limit = 3
        if (cachePageLimit > 3) {
            limit = cachePageLimit
        } else if (cachePageLimit < 1) {
            limit = numberOfPages
        }
        return limit
    }
    
    private var isStarted = false
    private var pageIndex: Int!
    private var prevPageIndex: Int?
    
    private var isWaitingForPageChangedCallback = false
    private var pageChangedCallback: (Void -> Void)?
    
    private var tabSectionHeight: CGFloat = 0
    private var contentSectionHeight: CGFloat = 0
    
    // MARK: DataSource
    private var numberOfPages = 0
    
    private func widthForTabAtIndex(index: Int) -> CGFloat {
        return cachedPageTabs[index]?.frame.width ?? 0
    }
    
    private func tabViewForPageAtIndex(index: Int) -> UIView? {
        return dataSource?.tabScrollView(self, tabViewForPageAtIndex: index)
    }
    
    private func contentViewForPageAtIndex(index: Int) -> UIView? {
        return dataSource?.tabScrollView(self, contentViewForPageAtIndex: index)
    }
    
    // MARK: Init
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        
        // init views
        tabSectionScrollView = UIScrollView()
        contentSectionScrollView = UIScrollView()
        self.addSubview(tabSectionScrollView)
        self.addSubview(contentSectionScrollView)
        
        tabSectionScrollView.pagingEnabled = false
        tabSectionScrollView.showsHorizontalScrollIndicator = false
        tabSectionScrollView.showsVerticalScrollIndicator = false
        tabSectionScrollView.delegate = self
        
        contentSectionScrollView.pagingEnabled = pagingEnabled
        contentSectionScrollView.showsHorizontalScrollIndicator = false
        contentSectionScrollView.showsVerticalScrollIndicator = false
        contentSectionScrollView.delegate = self
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
    }
    
    override public func layoutSubviews() {
        super.layoutSubviews()
        
        // reset status and stop scrolling immediately
        isStarted = false
        stopScrolling()
        
        // async necessarily
        dispatch_async(dispatch_get_main_queue()) {
            // set custom attrs
            self.tabSectionScrollView.backgroundColor = self.tabSectionBackgroundColor
            self.contentSectionScrollView.backgroundColor = self.contentSectionBackgroundColor
            
            // first time setup pages
            self.setupPages()
            
            // first time set defaule pageIndex
            self.initWithPageIndex(self.pageIndex ?? self.defaultPage)
            self.isStarted = true
            
            // load pages
            self.lazyLoadPages()
        }
    }
    
    // MARK: - Tab Clicking Control
    func tabViewDidClick(sensor: UITapGestureRecognizer) {
        activeScrollView = tabSectionScrollView
        moveToIndex(sensor.view!.tag, animated: true)
    }
    
    func tabSectionScrollViewDidClick(sensor: UITapGestureRecognizer) {
        activeScrollView = tabSectionScrollView
        moveToIndex(pageIndex, animated: true)
    }
    
    // MARK: - Scrolling Control
    private var activeScrollView: UIScrollView?
    
    // scrolling animation begin by dragging
    public func scrollViewWillBeginDragging(scrollView: UIScrollView) {
        activeScrollView = scrollView
        // stop current scrolling before start another scrolling
        stopScrolling()
    }
    
    // scrolling animation stop with decelerating
    public func scrollViewDidEndDecelerating(scrollView: UIScrollView) {
        moveToIndex(currentPageIndex(), animated: true)
    }
    
    // scrolling animation stop without decelerating
    public func scrollViewDidEndDragging(scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if (!decelerate) {
            moveToIndex(currentPageIndex(), animated: true)
        }
    }
    
    // scrolling animation stop programmatically
    public func scrollViewDidEndScrollingAnimation(scrollView: UIScrollView) {
        if (isWaitingForPageChangedCallback) {
            isWaitingForPageChangedCallback = false
            pageChangedCallback?()
        }
    }
    
    // scrolling
    public func scrollViewDidScroll(scrollView: UIScrollView) {
        let currentIndex = currentPageIndex()
        
        if (scrollView == activeScrollView) {
            let speed = self.frame.width / widthForTabAtIndex(currentIndex)
            let halfWidth = self.frame.width / 2
            
            var tabsWidth: CGFloat = 0
            var contentsWidth: CGFloat = 0
            for i in 0 ..< currentIndex {
                tabsWidth += widthForTabAtIndex(i)
                contentsWidth += self.frame.width
            }
            
            if (scrollView == tabSectionScrollView) {
                contentSectionScrollView.contentOffset.x = ((tabSectionScrollView.contentOffset.x + halfWidth - tabsWidth) * speed) + contentsWidth - halfWidth
            }
            
            if (scrollView == contentSectionScrollView) {
                tabSectionScrollView.contentOffset.x = ((contentSectionScrollView.contentOffset.x + halfWidth - contentsWidth) / speed) + tabsWidth - halfWidth
            }
            updateTabAppearance()
        }
        
        if (isStarted && pageIndex != currentIndex) {
            // set index
            pageIndex = currentIndex
            
            // lazy loading
            lazyLoadPages()
            
            // callback
            delegate?.tabScrollView(self, didScrollPageTo: currentIndex)
        }
    }
    
    // MARK: Public Methods
//    func scroll(offsetX: CGFloat) {
//    }
    
    public func reloadData() {
        // setup pages
        setupPages()
        
        // load pages
        lazyLoadPages()
    }
    
    public func changePageToIndex(index: Int, animated: Bool) {
        activeScrollView = tabSectionScrollView
        moveToIndex(index, animated: animated)
    }
    
    public func changePageToIndex(index: Int, animated: Bool, completion: (Void -> Void)) {
        isWaitingForPageChangedCallback = true
        pageChangedCallback = completion
        changePageToIndex(index, animated: animated)
    }
    
    // MARK: Private Methods
    private func stopScrolling() {
        tabSectionScrollView.setContentOffset(tabSectionScrollView.contentOffset, animated: false)
        contentSectionScrollView.setContentOffset(contentSectionScrollView.contentOffset, animated: false)
    }
    
    private func initWithPageIndex(index: Int) {
        // set pageIndex
        pageIndex = index
        prevPageIndex = pageIndex
        
        // init UI
        if (numberOfPages != 0) {
            var tabOffsetX = 0 as CGFloat
            var contentOffsetX = 0 as CGFloat
            for _ in 0 ..< index {
                tabOffsetX += widthForTabAtIndex(index)
                contentOffsetX += self.frame.width
            }
            // set default position of tabs and contents
            tabSectionScrollView.contentOffset = CGPoint(x: tabOffsetX + tabSectionScrollView.contentInset.left * -1, y: tabSectionScrollView.contentOffset.y)
            contentSectionScrollView.contentOffset = CGPoint(x: contentOffsetX  + contentSectionScrollView.contentInset.left * -1, y: contentSectionScrollView.contentOffset.y)
            updateTabAppearance(animated: false)
        }
    }
    
    private func currentPageIndex() -> Int {
        let width = self.frame.width
        var currentPageIndex = Int((contentSectionScrollView.contentOffset.x + (0.5 * width)) / width)
        if (currentPageIndex < 0) {
            currentPageIndex = 0
        } else if (currentPageIndex >= self.numberOfPages) {
            currentPageIndex = self.numberOfPages - 1
        }
        return currentPageIndex
    }

    private func setupPages() {
        // reset number of pages
        numberOfPages = dataSource?.numberOfPagesInTabScrollView(self) ?? 0
        
        // clear all caches
        cachedPageTabs.removeAll()
        for subview in tabSectionScrollView.subviews {
            subview.removeFromSuperview()
        }
        cachedPageContents.removeAll()
        for subview in contentSectionScrollView.subviews {
            subview.removeFromSuperview()
        }
        
        if (numberOfPages != 0) {
            // setup tabs first, and set contents later (lazyLoadPages)
            var tabSectionScrollViewContentWidth: CGFloat = 0
            for i in 0 ..< numberOfPages {
                if let tabView = tabViewForPageAtIndex(i) {
                    tabView.frame = CGRect(
                        x: tabSectionScrollViewContentWidth,
                        y: 0,
                        width: dataSource?.tabScrollView(self, widthForTabAtIndex: i) ?? 0,
                        height: tabSectionScrollView.frame.size.height)
                    // bind event
                    tabView.tag = i
                    tabView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: "tabViewDidClick:"))
                    cachedPageTabs[i] = tabView
                    tabSectionScrollView.addSubview(tabView)
                }
                tabSectionScrollViewContentWidth += widthForTabAtIndex(i)
            }
            
            // reset the fixed size of tab section
            tabSectionHeight = defaultTabHeight
            tabSectionScrollView.frame = CGRect(x: 0, y: 0, width: self.frame.size.width, height: tabSectionHeight)
            tabSectionScrollView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: "tabSectionScrollViewDidClick:"))
            tabSectionScrollView.contentInset = UIEdgeInsets(
                top: 0,
                left: (self.frame.width / 2) - (widthForTabAtIndex(0) / 2),
                bottom: 0,
                right: (self.frame.width / 2) - (widthForTabAtIndex(numberOfPages - 1) / 2))
            tabSectionScrollView.contentSize = CGSize(width: tabSectionScrollViewContentWidth, height: tabSectionHeight)
            
            // reset the fixed size of content section
            contentSectionHeight = self.frame.size.height - tabSectionHeight
            contentSectionScrollView.frame = CGRect(x: 0, y: tabSectionHeight, width: self.frame.size.width, height: contentSectionHeight)
        }
    }
    
    private func updateTabAppearance(animated animated: Bool = true) {
        if (tabGradient) {
            if (numberOfPages != 0) {
                for i in 0 ..< numberOfPages {
                    var alpha: CGFloat = 1.0
                    
                    let offset = abs(i - pageIndex)
                    if (offset > 1) {
                        alpha = 0.2
                    } else if (offset > 0) {
                        alpha = 0.4
                    } else {
                        alpha = 1.0
                    }
                    
                    if let tab = self.cachedPageTabs[i] {
                        if (animated) {
                            UIView.animateWithDuration(NSTimeInterval(0.5), animations: { () in
                                tab.alpha = alpha
                                return
                            })
                        } else {
                            tab.alpha = alpha
                        }
                    }
                }
            }
        }
    }
    
    private func moveToIndex(index: Int, animated: Bool) {
        if (index >= 0 && index < numberOfPages) {
            if (pagingEnabled) {
                // force stop
                stopScrolling()
                
                if (activeScrollView == nil || activeScrollView == tabSectionScrollView) {
                    activeScrollView = contentSectionScrollView
                    contentSectionScrollView.scrollRectToVisible(CGRect(
                        origin: CGPoint(x: self.frame.width * CGFloat(index), y: 0),
                        size: self.frame.size), animated: true)
                }
            }
            
            if (prevPageIndex != index) {
                prevPageIndex = index
                // callback
                delegate?.tabScrollView(self, didChangePageTo: index)
            }
        }
    }
    
    private func lazyLoadPages() {
        if (numberOfPages != 0) {
            let offset = 1
            let leftBoundIndex = pageIndex - offset > 0 ? pageIndex - offset : 0
            let rightBoundIndex = pageIndex + offset < numberOfPages ? pageIndex + offset : numberOfPages - 1
            
            var currentContentWidth: CGFloat = 0.0
            for i in 0 ..< numberOfPages {
                let width = self.frame.width
                if (i >= leftBoundIndex && i <= rightBoundIndex) {
                    let frame = CGRect(
                        x: currentContentWidth,
                        y: 0,
                        width: width,
                        height: contentSectionScrollView.frame.size.height)
                    insertPageAtIndex(i, frame: frame)
                }
                
                currentContentWidth += width
            }
            contentSectionScrollView.contentSize = CGSize(width: currentContentWidth, height: contentSectionHeight)
            
            // remove older caches
            while (cachedPageContents.count > realCachePageLimit) {
                if let (_, view) = cachedPageContents.popFirst() {
                    view.removeFromSuperview()
                }
            }
        }
    }
    
    private func insertPageAtIndex(index: Int, frame: CGRect) {
        if (cachedPageContents[index] == nil) {
            if let view = contentViewForPageAtIndex(index) {
                view.frame = frame
                cachedPageContents[index] = view
                contentSectionScrollView.addSubview(view)
            }
        } else {
            cachedPageContents.awake(index)
        }
    }
    
}

public struct CacheQueue<Key: Hashable, Value> {
    
    var keys: Array<Key> = []
    var values: Dictionary<Key, Value> = [:]
    var count: Int {
        return keys.count
    }
    
    subscript(key: Key) -> Value? {
        get {
            return values[key]
        }
        set {
            // key/value pair exists, delete it first
            if let index = keys.indexOf(key) {
                keys.removeAtIndex(index)
            }
            // append key
            if (newValue != nil) {
                keys.append(key)
            }
            // set value
            values[key] = newValue
        }
    }
    
    mutating func awake(key: Key) {
        if let index = keys.indexOf(key) {
            keys.removeAtIndex(index)
            keys.append(key)
        }
    }
    
    mutating func popFirst() -> (Key, Value)? {
        let key = keys.removeFirst()
        if let value = values.removeValueForKey(key) {
            return (key, value)
        } else {
            return nil
        }
    }
    
    mutating func removeAll() {
        keys.removeAll()
        values.removeAll()
    }
    
}
