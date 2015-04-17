//
//  UIScrollView+InfiniteTopScroll.h
//
//  UIScrollView infinite scroll category
//
//  Created by Andrej Mihajlov on 9/4/13.
//  Copyright (c) 2013-2015 Andrej Mihajlov. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface UIScrollView (InfiniteTopScroll)

/**
 *  Infinite scroll activity indicator style (default: UIActivityIndicatorViewStyleGray)
 */
@property (nonatomic) UIActivityIndicatorViewStyle infiniteTopScrollIndicatorStyle;

/**
 *  Infinite indicator view
 *
 *  You can set your own custom view instead of default activity indicator, 
 *  make sure it implements methods below:
 *
 *  * `- (void)startAnimating`
 *  * `- (void)stopAnimating`
 *
 *  Infinite scroll will call implemented methods during user interaction.
 */
@property (nonatomic) UIView* infiniteTopScrollIndicatorView;

/**
 *  Vertical margin around indicator view (Default: 11)
 */
@property (nonatomic) CGFloat infiniteTopScrollIndicatorMargin;

/**
 *  Sets the offset between the real end of the scroll view content and the scroll position, so the handler can be triggered before reaching end.
 *  Defaults to 0.0;
 */
@property (nonatomic) CGFloat infiniteTopScrollTriggerOffset;

/**
 *  Setup infinite scroll handler
 *
 *  @param handler a handler block
 */
- (void)addInfiniteTopScrollWithHandler:(void(^)(UIScrollView* scrollView))handler;

/**
 *  Unregister infinite scroll
 */
- (void)removeInfiniteTopScroll;

/**
 *  Finish infinite scroll animations
 *
 *  You must call this method from your infinite scroll handler to finish all
 *  animations properly and reset infinite scroll state
 *
 *  @param handler a completion block handler called when animation finished
 */
- (void)finishInfiniteTopScrollWithCompletion:(void(^)(UIScrollView* scrollView))handler;

/**
 *  Finish infinite scroll animations
 *
 *  You must call this method from your infinite scroll handler to finish all
 *  animations properly and reset infinite scroll state
 */
- (void)finishInfiniteTopScroll;

@end
