#import <AppKit/AppKit.h>
#import "TUCTouchInputManager.h"
#import "TUCCursorUtilities.h"

// Test seams override only the clock and the final CGEventPost I/O boundary.
@interface TUCTouchInputManager (Testing)
- (instancetype)initWithCursorUtilities:(TUCCursorUtilities *)utilities;
- (NSTimeInterval)inputTime;
@end
@interface TUCCursorUtilities (Testing)
- (void)postMouseEvent:(CGEventRef)event;
@end
@interface RecordingCursor : TUCCursorUtilities
@property NSMutableArray<NSDictionary *> *events;
@end
@implementation RecordingCursor
- (instancetype)init { if ((self = [super init])) _events = [NSMutableArray new]; return self; }
- (void)postMouseEvent:(CGEventRef)event {
    [self.events addObject:@{@"type": @(CGEventGetType(event)), @"count": @(CGEventGetIntegerValueField(event, kCGMouseEventClickState)), @"point": [NSValue valueWithPoint:CGEventGetLocation(event)]}];
}
@end
@interface TestManager : TUCTouchInputManager
@property NSTimeInterval now;
@end
@implementation TestManager
- (NSTimeInterval)inputTime { return self.now; }
@end
@interface TestDelegate : NSObject <TUCTouchDelegate>
@property TUCScreen *screen;
@property TUCCursorAction dragAction;
@end
@implementation TestDelegate
- (instancetype)init {
    if ((self = [super init])) {
        _screen = [TUCScreen new];
        _screen.frame = CGRectMake(100, -200, 1000, 500);
        _screen.nativeResolution = CGSizeMake(1000, 500);
        _screen.nativePhysicalSize = CGSizeMake(500, 250);
        _dragAction = TUCCursorActionMove;
    }
    return self;
}
- (void)touchesDidChange {}
- (void)touchscreenDidConnectWithLocationID:(uint32_t)locationID {}
- (void)touchscreenDidDisconnectWithLocationID:(uint32_t)locationID {}
- (TUCScreen *)touchscreenForLocationID:(uint32_t)locationID { return self.screen; }
- (CGFloat)digitizerRotationForLocationID:(uint32_t)locationID { return 0; }
- (TUCCursorAction)actionForGesture:(TUCCursorGesture)gesture {
    if (gesture == TUCCursorGestureTap) return TUCCursorActionClick;
    if (gesture == TUCCursorGestureHoldAndDrag) return TUCCursorActionDrag;
    if (gesture == TUCCursorGestureDrag) return self.dragAction;
    return TUCCursorActionMove;
}
@end
// HID lifecycle is stubbed: these tests must never open or seize real devices.
void OpenHIDManager(void *manager) {}
void CloseHIDManager(void) {}
void SetTouchDevicesSeized(Boolean seized) {}

static int checks = 0;
#define CHECK(condition) do { checks++; if (!(condition)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #condition); exit(1); } } while (0)
static void report(TestManager *m, int contact, double x, double y, BOOL down) {
    TouchInputManagerUpdateTouchPosition((__bridge void *)m, 1, contact, x, y, down, YES);
    TouchInputManagerDidProcessReport((__bridge void *)m, 1);
}
static void expectTypes(RecordingCursor *c, NSArray *types) {
    CHECK([[c.events valueForKey:@"type"] isEqual:types]);
}
static TestManager *fresh(RecordingCursor **cursor, TestDelegate *delegate) {
    *cursor = [RecordingCursor new];
    TestManager *m = [[TestManager alloc] initWithCursorUtilities:*cursor];
    m.delegate = delegate; m.now = 100; m.stationaryThreshold = .1; m.errorResistance = 4;
    m.drawingModeEnabled = YES;
    return m;
}
int main(void) { @autoreleasepool {
    TestDelegate *d = [TestDelegate new]; RecordingCursor *c;
    TestManager *m = fresh(&c, d);
    // Immediate down, sub-jitter movement, hold, final location, one release.
    report(m, 1, .2, .2, YES);
    expectTypes(c, @[@1]); CHECK([c.events[0][@"point"] pointValue].x == 300);
    report(m, 1, .2001, .2, YES); m.now += 2;
    report(m, 1, .2001, .2, YES); report(m, 1, .4, .4, NO);
    expectTypes(c, @[@1, @6, @6, @2]);
    CHECK(CGPointEqualToPoint([c.events.lastObject[@"point"] pointValue], CGPointMake(500,400)));
    TouchInputManagerDidProcessReport((__bridge void *)m, 1);
    CHECK(c.events.count == 4);

    // Matching taps use count 2 on both down and up, with system click interval.
    m = fresh(&c,d); report(m,1,.5,.5,YES); report(m,1,.5,.5,NO);
    m.now += NSEvent.doubleClickInterval / 2;
    report(m,1,.502,.502,YES); report(m,1,.502,.502,NO);
    expectTypes(c,@[@1,@2,@1,@2]); CHECK([c.events[2][@"count"] intValue] == 2); CHECK([c.events[3][@"count"] intValue] == 2);
    // Every direction and axis, plus diagonal radial distance, rejects distant taps.
    for (NSValue *point in @[[NSValue valueWithPoint:CGPointMake(.2,.5)], [NSValue valueWithPoint:CGPointMake(.8,.5)], [NSValue valueWithPoint:CGPointMake(.5,.2)], [NSValue valueWithPoint:CGPointMake(.5,.8)], [NSValue valueWithPoint:CGPointMake(.508,.516)]]) {
        m = fresh(&c,d); report(m,1,.5,.5,YES); report(m,1,.5,.5,NO); m.now += .01;
        CGPoint p = point.pointValue; report(m,1,p.x,p.y,YES); CHECK([c.events.lastObject[@"count"] intValue] == 1);
    }
    m = fresh(&c,d); report(m,1,.5,.5,YES); report(m,1,.5,.5,NO); m.now += NSEvent.doubleClickInterval + .01;
    report(m,1,.5,.5,YES); CHECK([c.events.lastObject[@"count"] intValue] == 1);
    // A slow stroke returning to its start and a long hold are not prior taps.
    for (NSNumber *hold in @[@NO,@YES]) {
        m = fresh(&c,d); report(m,1,.5,.5,YES);
        if (hold.boolValue) m.now += 2; else { report(m,1,.52,.5,YES); report(m,1,.5,.5,YES); }
        report(m,1,.5,.5,NO); m.now += .01; report(m,1,.5,.5,YES);
        CHECK([c.events.lastObject[@"count"] intValue] == 1);
    }
    // Extra fingers cannot steal primary ownership, click, scroll, or pinch.
    m = fresh(&c,d); report(m,1,.2,.2,YES); report(m,2,.8,.8,YES);
    report(m,1,.3,.3,YES); report(m,1,.3,.3,NO); report(m,2,.7,.7,YES);
    report(m,3,.6,.6,YES); report(m,2,.7,.7,NO); report(m,3,.6,.6,NO);
    expectTypes(c,@[@1,@6,@2]); report(m,4,.4,.4,YES); CHECK(c.events.count == 4);
    // Mode/output changes release immediately and require all held contacts to lift.
    for (NSNumber *mode in @[@NO,@YES]) {
        m = fresh(&c,d); report(m,1,.2,.2,YES);
        if (mode.boolValue) { m.drawingModeEnabled = NO; m.drawingModeEnabled = YES; }
        else { m.postMouseEvents = NO; m.postMouseEvents = YES; }
        report(m,1,.3,.3,YES); report(m,2,.8,.8,YES); report(m,1,.3,.3,NO); report(m,2,.8,.8,NO);
        expectTypes(c,@[@1,@2]); report(m,1,.4,.4,YES); CHECK(c.events.count == 3);
    }
    // Zero distance allows exactly matching taps; cancellation never resumes a held contact.
    m = fresh(&c,d); m.doubleClickTolerance = 0;
    report(m,1,.5,.5,YES); report(m,1,.5,.5,NO); m.now += .01;
    report(m,1,.5,.5,YES); CHECK([c.events.lastObject[@"count"] intValue] == 2);
    [m cancelCurrentInput]; report(m,1,.6,.6,YES); report(m,1,.6,.6,NO);
    expectTypes(c,@[@1,@2,@1,@2]); report(m,1,.5,.5,YES);
    CHECK([c.events.lastObject[@"count"] intValue] == 1);
    // Contact IDs are local to a device; another device cannot steal or release the owner.
    m = fresh(&c,d); report(m,1,.2,.2,YES);
    TouchInputManagerUpdateTouchPosition((__bridge void *)m,2,1,.8,.8,YES,YES);
    TouchInputManagerDidProcessReport((__bridge void *)m,2);
    TouchInputManagerDidDisconnectTouchscreen((__bridge void *)m,2);
    expectTypes(c,@[@1]); report(m,1,.3,.3,YES); report(m,1,.3,.3,NO);
    expectTypes(c,@[@1,@6,@2]);
    // Lost reports cancel exactly once; origin liftoff still releases.
    m = fresh(&c,d); m.errorResistance = 0; report(m,1,.2,.2,YES);
    TouchInputManagerDidProcessReport((__bridge void *)m,1); TouchInputManagerDidProcessReport((__bridge void *)m,1);
    expectTypes(c,@[@1,@2]);
    m = fresh(&c,d); m.ignoreOriginTouches = YES; report(m,1,.2,.2,YES); report(m,1,0,0,NO); expectTypes(c,@[@1,@2]);
    CHECK(CGPointEqualToPoint([c.events.lastObject[@"point"] pointValue],CGPointMake(300,300)));
    // Device loss, stop, explicit cancellation and deallocation each balance the button.
    for (int action=0; action<4; action++) {
        m = fresh(&c,d); report(m,1,.2,.2,YES);
        if (action==0) TouchInputManagerDidDisconnectTouchscreen((__bridge void *)m,1);
        if (action==1) { [m stop]; [m stop]; }
        if (action==2) { [m cancelCurrentInput]; [m cancelCurrentInput]; }
        if (action==3) m = nil;
        expectTypes(c,@[@1,@2]);
    }
    // Reconnection accepts the next fresh contact, with no stale cancellation barrier.
    m = fresh(&c,d); report(m,1,.2,.2,YES);
    TouchInputManagerDidDisconnectTouchscreen((__bridge void *)m,1);
    TouchInputManagerDidConnectTouchscreen((__bridge void *)m,1);
    report(m,1,.4,.4,YES); expectTypes(c,@[@1,@2,@1]);
    // Missing physical dimensions must not make every location count as nearby.
    m = fresh(&c,d); d.screen.nativePhysicalSize = CGSizeZero;
    report(m,1,.2,.2,YES); report(m,1,.2,.2,NO); m.now += .01;
    report(m,1,.8,.8,YES); CHECK([c.events.lastObject[@"count"] intValue] == 1);
    d.screen.nativePhysicalSize = CGSizeMake(500,250);
    // Default remains legacy, and existing move/scroll/point-and-click dispatch remains intact.
    for (NSNumber *action in @[@(TUCCursorActionMove),@(TUCCursorActionScroll),@(TUCCursorActionPointAndClick)]) {
        c = [RecordingCursor new]; m = [[TestManager alloc] initWithCursorUtilities:c]; m.delegate=d;
        CHECK(!m.drawingModeEnabled); d.dragAction=action.unsignedIntegerValue;
        report(m,1,.2,.2,YES); report(m,1,.4,.4,YES); report(m,1,.4,.4,NO);
        if (d.dragAction == TUCCursorActionMove) expectTypes(c,@[@5,@5,@5]);
        if (d.dragAction == TUCCursorActionScroll) expectTypes(c,@[@5,@22,@22]);
        if (d.dragAction == TUCCursorActionPointAndClick) expectTypes(c,@[@5,@5,@5,@1,@2]);
        [m cancelCurrentInput];
    }
    printf("PASS: %d assertions; constructed CGEvents recorded without posting or HID access.\n", checks);
} return 0; }
