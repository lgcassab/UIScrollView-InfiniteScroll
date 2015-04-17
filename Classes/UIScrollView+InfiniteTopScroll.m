//
//  UIScrollView+InfiniteTopScroll.m
//
//  UIScrollView infinite scroll category
//
//  Created by Andrej Mihajlov on 9/4/13.
//  Copyright (c) 2013-2015 Andrej Mihajlov. All rights reserved.
//

#import "UIScrollView+InfiniteTopScroll.h"
#import <objc/runtime.h>

#define TRACE_ENABLED 1

#if TRACE_ENABLED
#   define TRACE(_format, ...) NSLog(_format, ##__VA_ARGS__)
#else
#   define TRACE(_format, ...)
#endif

static void PBSwizzleMethod(Class c, SEL original, SEL alternate) {
    Method origMethod = class_getInstanceMethod(c, original);
    Method newMethod = class_getInstanceMethod(c, alternate);
    
    if(class_addMethod(c, original, method_getImplementation(newMethod), method_getTypeEncoding(newMethod))) {
        class_replaceMethod(c, alternate, method_getImplementation(origMethod), method_getTypeEncoding(origMethod));
    } else {
        method_exchangeImplementations(origMethod, newMethod);
    }
}

// Animation duration used for setContentOffset:
static const NSTimeInterval kPBInfiniteTopScrollAnimationDuration = 0.35;

// Keys for values in associated dictionary
static const void *kPBInfiniteTopScrollHandlerKey			= &kPBInfiniteTopScrollHandlerKey;
static const void *kPBInfiniteTopScrollIndicatorViewKey		= &kPBInfiniteTopScrollIndicatorViewKey;
static const void *kPBInfiniteTopScrollIndicatorStyleKey	= &kPBInfiniteTopScrollIndicatorStyleKey;
static const void *kPBInfiniteTopScrollStateKey				= &kPBInfiniteTopScrollStateKey;
static const void *kPBInfiniteTopScrollInitKey				= &kPBInfiniteTopScrollInitKey;
static const void *kPBInfiniteTopScrollExtraBottomInsetKey	= &kPBInfiniteTopScrollExtraBottomInsetKey;
static const void *kPBInfiniteTopScrollIndicatorMarginKey	= &kPBInfiniteTopScrollIndicatorMarginKey;
static const void *kPBInfiniteTopScrollTriggerOffsetKey		= &kPBInfiniteTopScrollTriggerOffsetKey;

// Infinite scroll states
typedef NS_ENUM(NSInteger, PBInfiniteTopScrollState) {
    PBInfiniteTopScrollStateNone,
    PBInfiniteTopScrollStateLoading
};

// Private category on UIScrollView to define dynamic properties
@interface UIScrollView ()

// Infinite scroll handler block
@property (copy, nonatomic, setter=pb_top_setInfiniteTopScrollHandler:, getter=pb_top_infiniteTopScrollHandler)
void(^pb_top_infiniteTopScrollHandler)(UIScrollView* scrollView);

// Infinite scroll state
@property (nonatomic, setter=pb_top_setInfiniteTopScrollState:, getter=pb_top_infiniteTopScrollState)
PBInfiniteTopScrollState pb_top_infiniteTopScrollState;

// A flag that indicates whether scroll is initialized
@property (nonatomic, setter=pb_top_setInfiniteTopScrollInitialized:, getter=pb_top_infiniteTopScrollInitialized)
BOOL pb_top_infiniteTopScrollInitialized;

// Extra padding to push indicator view below view bounds.
// Used in case when content size is smaller than view bounds
@property (nonatomic, setter=pb_top_setInfiniteTopScrollExtraBottomInset:, getter=pb_top_infiniteTopScrollExtraBottomInset)
CGFloat pb_top_infiniteTopScrollExtraBottomInset;

@end

@implementation UIScrollView (InfiniteTopScroll)

#pragma mark - Initialization Methods

+ (void)load {
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		PBSwizzleMethod(self, @selector(setContentOffset:), @selector(pb_top_setContentOffset:));
		PBSwizzleMethod(self, @selector(setContentSize:), @selector(pb_top_setContentSize:));
	});
}

#pragma mark - Public methods

- (void)addInfiniteTopScrollWithHandler:(void(^)(UIScrollView* scrollView))handler {
    // Save handler block
    self.pb_top_infiniteTopScrollHandler = handler;
    
    // Double initialization only replaces handler block
    // Do not continue if already initialized
    if(self.pb_top_infiniteTopScrollInitialized) {
        return;
    }
    
    // Add pan guesture handler
    [self.panGestureRecognizer addTarget:self action:@selector(pb_top_handlePanGesture:)];
    
    // Mark infiniteTopScroll initialized
    self.pb_top_infiniteTopScrollInitialized = YES;
}

- (void)removeInfiniteTopScroll {
    // Ignore multiple calls to remove infinite scroll
    if(!self.pb_top_infiniteTopScrollInitialized) {
        return;
    }
    
    // Remove pan gesture handler
    [self.panGestureRecognizer removeTarget:self action:@selector(pb_top_handlePanGesture:)];
    
    // Destroy infinite scroll indicator
    [self.infiniteTopScrollIndicatorView removeFromSuperview];
    self.infiniteTopScrollIndicatorView = nil;
    
    // Mark infinite scroll as uninitialized
    self.pb_top_infiniteTopScrollInitialized = NO;
}

- (void)finishInfiniteTopScroll {
    [self finishInfiniteTopScrollWithCompletion:nil];
}

- (void)finishInfiniteTopScrollWithCompletion:(void(^)(UIScrollView* scrollView))handler {
    if(self.pb_top_infiniteTopScrollState == PBInfiniteTopScrollStateLoading) {
        [self pb_top_stopAnimatingInfiniteTopScrollWithCompletion:handler];
    }
}

- (void)setInfiniteTopScrollIndicatorStyle:(UIActivityIndicatorViewStyle)infiniteTopScrollIndicatorStyle {
    objc_setAssociatedObject(self, kPBInfiniteTopScrollIndicatorStyleKey, @(infiniteTopScrollIndicatorStyle), OBJC_ASSOCIATION_ASSIGN);
    id activityIndicatorView = self.infiniteTopScrollIndicatorView;
    if([activityIndicatorView isKindOfClass:[UIActivityIndicatorView class]]) {
        [activityIndicatorView setActivityIndicatorViewStyle:infiniteTopScrollIndicatorStyle];
    }
}

- (UIActivityIndicatorViewStyle)infiniteTopScrollIndicatorStyle {
    NSNumber* indicatorStyle = objc_getAssociatedObject(self, kPBInfiniteTopScrollIndicatorStyleKey);
    if(indicatorStyle) {
        return indicatorStyle.integerValue;
    }
    return UIActivityIndicatorViewStyleGray;
}

- (void)setInfiniteTopScrollIndicatorView:(UIView*)indicatorView {
    // make sure indicator is initially hidden
    indicatorView.hidden = YES;
    
    objc_setAssociatedObject(self, kPBInfiniteTopScrollIndicatorViewKey, indicatorView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (UIView*)infiniteTopScrollIndicatorView {
    return objc_getAssociatedObject(self, kPBInfiniteTopScrollIndicatorViewKey);
}

- (void)setInfiniteTopScrollIndicatorMargin:(CGFloat)infiniteTopScrollIndicatorMargin {
    objc_setAssociatedObject(self, kPBInfiniteTopScrollIndicatorMarginKey, @(infiniteTopScrollIndicatorMargin), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (CGFloat)infiniteTopScrollIndicatorMargin {
    NSNumber* margin = objc_getAssociatedObject(self, kPBInfiniteTopScrollIndicatorMarginKey);
    if(margin) {
        return margin.floatValue;
    }
    // Default row height minus activity indicator height
    return 11;
}

- (void)setInfiniteTopScrollTriggerOffset:(CGFloat)infiniteTopScrollTriggerOffset {
    objc_setAssociatedObject(self, kPBInfiniteTopScrollTriggerOffsetKey,
							 @(infiniteTopScrollTriggerOffset),
							 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (CGFloat)infiniteTopScrollTriggerOffset {
    NSNumber* offset = objc_getAssociatedObject(self, kPBInfiniteTopScrollTriggerOffsetKey);
    if(offset) {
        return offset.floatValue;
    }

    return 0;
}

#pragma mark - Private dynamic properties

- (PBInfiniteTopScrollState)pb_top_infiniteTopScrollState {
    NSNumber* state = objc_getAssociatedObject(self, kPBInfiniteTopScrollStateKey);
    return [state integerValue];
}

- (void)pb_top_setInfiniteTopScrollState:(PBInfiniteTopScrollState)state {
    objc_setAssociatedObject(self, kPBInfiniteTopScrollStateKey, @(state), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    TRACE(@"pb_top_setInfiniteTopScrollState = %ld", (long)state);
}

- (void)pb_top_setInfiniteTopScrollHandler:(void(^)(UIScrollView* scrollView))handler {
    objc_setAssociatedObject(self, kPBInfiniteTopScrollHandlerKey, handler, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (void(^)(UIScrollView* scrollView))pb_top_infiniteTopScrollHandler {
    return objc_getAssociatedObject(self, kPBInfiniteTopScrollHandlerKey);
}

- (void)pb_top_setInfiniteTopScrollExtraBottomInset:(CGFloat)height {
    objc_setAssociatedObject(self, kPBInfiniteTopScrollExtraBottomInsetKey, @(height), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (CGFloat)pb_top_infiniteTopScrollExtraBottomInset {
    return [objc_getAssociatedObject(self, kPBInfiniteTopScrollExtraBottomInsetKey) doubleValue];
}

- (BOOL)pb_top_infiniteTopScrollInitialized {
    NSNumber* flag = objc_getAssociatedObject(self, kPBInfiniteTopScrollInitKey);
    
    return [flag boolValue];
}

- (void)pb_top_setInfiniteTopScrollInitialized:(BOOL)flag {
    objc_setAssociatedObject(self, kPBInfiniteTopScrollInitKey, @(flag), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - Gesture Recognizer

- (void)pb_top_handlePanGesture:(UITapGestureRecognizer*)gestureRecognizer {
    if (gestureRecognizer.state == UIGestureRecognizerStateEnded) {
        [self pb_top_scrollToInfiniteTopIndicatorIfNeeded];
    }
}

#pragma mark - Private methods

- (CGFloat)pb_top_adjustedHeightFromContentSize:(CGSize)contentSize {
    CGFloat remainingHeight = self.bounds.size.height - self.contentInset.top - self.contentInset.bottom;
    if(contentSize.height < remainingHeight) {
        return remainingHeight;
    }
    return contentSize.height;
}

- (void)pb_top_callInfiniteTopScrollHandler {
    if(self.pb_top_infiniteTopScrollHandler) {
        self.pb_top_infiniteTopScrollHandler(self);
    }
    TRACE(@"Call handler.");
}

- (UIView*)pb_top_getOrCreateActivityIndicatorView {
    UIView* activityIndicator = self.infiniteTopScrollIndicatorView;
    
    if(!activityIndicator) {
        activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:self.infiniteTopScrollIndicatorStyle];
        self.infiniteTopScrollIndicatorView = activityIndicator;
    }
    
    // Add activity indicator into scroll view if needed
    if(activityIndicator.superview != self) {
        [self addSubview:activityIndicator];
    }
    
    return activityIndicator;
}

- (CGFloat)pb_top_infiniteTopIndicatorRowHeight {
    UIView* activityIndicator = [self pb_top_getOrCreateActivityIndicatorView];
    CGFloat indicatorHeight = CGRectGetHeight(activityIndicator.bounds);
    
    return indicatorHeight + self.infiniteTopScrollIndicatorMargin * 2;
}

- (void)pb_top_positionInfiniteTopScrollIndicatorWithContentSize:(CGSize)size {
	
    // adjust content height for case when contentSize smaller than view bounds
    UIView* activityIndicator = [self pb_top_getOrCreateActivityIndicatorView];
    CGFloat indicatorViewHeight = CGRectGetHeight(activityIndicator.bounds);
	
    CGRect rect = activityIndicator.frame;
    rect.origin.x = size.width * 0.5 - CGRectGetWidth(rect) * 0.5;
	
	rect.origin.y = -(indicatorViewHeight + self.infiniteTopScrollIndicatorMargin * 1);
    
    if (!CGRectEqualToRect(rect, activityIndicator.frame)) {
        activityIndicator.frame = rect;
    }
}

- (void)pb_top_startAnimatingInfiniteTopScroll {
	
    UIView* activityIndicator = [self pb_top_getOrCreateActivityIndicatorView];
    
    [self pb_top_positionInfiniteTopScrollIndicatorWithContentSize:self.contentSize];
    
    activityIndicator.hidden = NO;
    
    if([activityIndicator respondsToSelector:@selector(startAnimating)]) {
        [activityIndicator performSelector:@selector(startAnimating) withObject:nil];
    }
    
    UIEdgeInsets contentInset = self.contentInset;
	
    // Make a room to accommodate indicator view
    contentInset.top += [self pb_top_infiniteTopIndicatorRowHeight];
    
    // We have to pad scroll view when content height is smaller than view bounds.
    // This will guarantee that indicator view appears at the very bottom of scroll view.
    CGFloat adjustedContentHeight = [self pb_top_adjustedHeightFromContentSize:self.contentSize];
    CGFloat extraBottomInset = adjustedContentHeight - self.contentSize.height;
    
    // Add empty space padding
    contentInset.top += extraBottomInset;
    
    // Save extra inset
    self.pb_top_infiniteTopScrollExtraBottomInset = extraBottomInset;
    
    TRACE(@"extraBottomInset = %.2f", extraBottomInset);
    
    self.pb_top_infiniteTopScrollState = PBInfiniteTopScrollStateLoading;
    [self pb_top_setScrollViewContentInset:contentInset animated:YES completion:^(BOOL finished) {
        if(finished) {
            [self pb_top_scrollToInfiniteTopIndicatorIfNeeded];
        }
    }];
    TRACE(@"Start animating.");
}

- (void)pb_top_stopAnimatingInfiniteTopScrollWithCompletion:(void(^)(UIScrollView* scrollView))handler {
    UIView* activityIndicator = self.infiniteTopScrollIndicatorView;
    UIEdgeInsets contentInset = self.contentInset;
	
    contentInset.top -= [self pb_top_infiniteTopIndicatorRowHeight];
	
    // remove extra inset added to pad infinite scroll
    contentInset.top -= self.pb_top_infiniteTopScrollExtraBottomInset;
    
    [self pb_top_setScrollViewContentInset:contentInset animated:YES completion:^(BOOL finished) {
        if ([activityIndicator respondsToSelector:@selector(stopAnimating)]) {
            [activityIndicator performSelector:@selector(stopAnimating) withObject:nil];
        }
        
        activityIndicator.hidden = YES;
        
        self.pb_top_infiniteTopScrollState = PBInfiniteTopScrollStateNone;
        
        // Initiate scroll to the bottom if due to user interaction contentOffset.y
        // stuck somewhere between last cell and activity indicator
        if (finished) {
            CGFloat newY = self.contentSize.height - self.bounds.size.height + self.contentInset.bottom;
            
            if (self.contentOffset.y > newY && newY > 0) {
                [self setContentOffset:CGPointMake(0, newY) animated:YES];
                TRACE(@"Stop animating and scroll to bottom.");
            }
        }
        
        // Call completion handler
        if (handler) {
            handler(self);
        }
    }];
    
    TRACE(@"Stop animating.");
}

//
// Scrolls down to activity indicator position if activity indicator is partially visible
//
- (void)pb_top_scrollToInfiniteTopIndicatorIfNeeded {
	
    if (![self isDragging] && self.pb_top_infiniteTopScrollState == PBInfiniteTopScrollStateLoading) {
		
        CGFloat indicatorRowHeight = [self pb_top_infiniteTopIndicatorRowHeight];
        
		CGFloat bottomBarHeight = (self.contentInset.top - indicatorRowHeight);
		CGFloat minY = bottomBarHeight;
		CGFloat maxY = minY - indicatorRowHeight;
		
        TRACE(@"minY = %.2f; maxY = %.2f; offsetY = %.2f", minY, maxY, self.contentOffset.y);
        
        if(self.contentOffset.y < minY && self.contentOffset.y > maxY) {
            TRACE(@"Scroll to infinite indicator.");
            [self setContentOffset:CGPointMake(0, maxY) animated:YES];
        }
    }
}

- (void)pb_top_setScrollViewContentInset:(UIEdgeInsets)contentInset
							animated:(BOOL)animated
						  completion:(void(^)(BOOL finished))completion {
	
    void(^animations)(void) = ^{
        self.contentInset = contentInset;
    };
    
    if(animated)
    {
        [UIView animateWithDuration:kPBInfiniteTopScrollAnimationDuration
                              delay:0.0
                            options:(UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState)
                         animations:animations
                         completion:completion];
    }
    else
    {
        [UIView performWithoutAnimation:animations];
        
        if(completion) {
            completion(YES);
        }
    }
}

#pragma mark - UIScrollView Methods

- (void)pb_top_setContentOffset:(CGPoint)contentOffset {
	[self pb_top_setContentOffset:contentOffset];
	
	if(self.pb_top_infiniteTopScrollInitialized) {
		[self pb_top_scrollViewDidScroll:contentOffset];
	}
}

- (void)pb_top_setContentSize:(CGSize)contentSize {
	[self pb_top_setContentSize:contentSize];
	
	if(self.pb_top_infiniteTopScrollInitialized) {
		[self pb_top_positionInfiniteTopScrollIndicatorWithContentSize:contentSize];
	}
}

- (void)pb_top_scrollViewDidScroll:(CGPoint)contentOffset {
	
	// The lower bound when infinite scroll should kick in
	CGFloat actionOffset = -([self pb_top_infiniteTopIndicatorRowHeight]);
	
	// Disable infinite scroll when scroll view is empty
	// Default UITableView reports height = 1 on empty tables
	BOOL hasActualContent = (self.contentSize.height > 1);
	
	if ([self isDragging] && hasActualContent && contentOffset.y < actionOffset) {
		if (self.pb_top_infiniteTopScrollState == PBInfiniteTopScrollStateNone) {
			TRACE(@"Action.");
			
			[self pb_top_startAnimatingInfiniteTopScroll];
			
			// This will delay handler execution until scroll deceleration
			[self performSelector:@selector(pb_top_callInfiniteTopScrollHandler)
					   withObject:self
					   afterDelay:0.1
						  inModes:@[ NSDefaultRunLoopMode ]];
		}
	}
}

@end
