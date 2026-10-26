//
//  TUCCursorUtilities.h
//  Touch Up Core
//
//  Created by Sebastian Hueber on 11.02.23.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface TUCCursorUtilities : NSObject

+ (instancetype)sharedInstance;


@property CGFloat doubleClickTolerance;

- (CGPoint)currentCursorLocation;

- (void)bringWindowToFrontAt:(CGPoint)aLocation;

- (void)moveCursorTo:(CGPoint)aLocation;

- (void)performClickAt:(CGPoint)aLocation;

- (void)performSecondaryClickAt:(CGPoint)aLocation;

- (void)dragCursorTo:(CGPoint)aLocation phase:(NSTouchPhase)phase;
- (void)stopDraggingCursor;

// Immediate input: exactly one down, zero or more drags, and one up.
- (void)beginDrawingAt:(CGPoint)location clickCount:(NSInteger)clickCount;
- (void)continueDrawingAt:(CGPoint)location;
- (void)endDrawingAt:(CGPoint)location;
- (void)cancelMomentumScroll;

- (void)scroll:(CGPoint)translation phase:(NSTouchPhase)phase;

- (void)magnifyLocationA:(CGPoint)p1 locationB:(CGPoint)p2 relativeP1:(CGPoint)r1 relP2:(CGPoint)r2;
- (void)stopMagnifying;


@end

NS_ASSUME_NONNULL_END
