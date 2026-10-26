//
//  TUCTouchInputManager.m
//  Touch Up Core
//
//  Created by Sebastian Hueber on 03.02.23.
//

#import "TUCTouchInputManager.h"

#import "HIDInterpreter.h"
#import "TUCCursorUtilities.h"

@interface TUCTouchInputManager ()

@property BOOL running;
@property (strong) TUCCursorUtilities *cursorUtilities;
@property (strong, nullable) TUCTouch *drawingTouch;
@property BOOL waitingForAllTouchesToLift;
@property CGPoint drawingStartLocation;
@property CGPoint drawingLastLocation;
@property NSTimeInterval drawingStartTime;
@property BOOL drawingQualifiedForTap;
@property NSInteger drawingClickCount;
@property BOOL hasPreviousDrawingTap;
@property CGPoint previousDrawingTapLocation;
@property uint32_t previousDrawingTapDevice;
@property NSTimeInterval previousDrawingTapTime;
@property NSInteger previousDrawingTapCount;

@property NSMutableDictionary<NSNumber *, NSNumber *> *frameIDsByLocationID;

@property (weak, nullable) TUCTouch *cursorTouch;
@property (weak, nullable) TUCTouch *gestureAdditionalTouch;

@property BOOL cursorTouchQualifiedForTap; // if the cursor entered moving state once it can no longer be interpreted as tap
@property BOOL cursorTouchDidHold; //
@property (strong) NSDate *cursorTouchStationarySinceDate;

@property CGFloat pinchDistance;

@property TUCCursorGesture identifiedMultitouchGesture;

@end


@implementation TUCTouchInputManager

#pragma mark   Start & Stop

- (void)start {
    if (self.running) return;
    self.running = YES;
    
    __weak id weakSelf = self;
    
    // needs to run on main anyway
//    [NSThread detachNewThreadWithBlock:^{
//        [NSThread setThreadPriority:1];
    OpenHIDManager((__bridge void *)(weakSelf));
//    }];
    
}

- (void)stop {
    [self cancelCurrentInput];
    [self.touchSet removeAllObjects];
    self.waitingForAllTouchesToLift = NO;
    if (self.running) {
        self.running = NO;
        CloseHIDManager();
    }
}

- (void)setTouchscreensSeized:(BOOL)seized {
    [self cancelCurrentInput];
    SetTouchDevicesSeized(seized);
}


- (void)didConnectTouchscreenWithLocationID:(uint32_t)locationID {
    self.frameIDsByLocationID[@(locationID)] = @0;
    [self.delegate touchscreenDidConnectWithLocationID:locationID];
}

- (void)didDisconnectTouchscreenWithLocationID:(uint32_t)locationID {
    if (self.drawingTouch.locationID == locationID || self.cursorTouch.locationID == locationID) {
        [self cancelCurrentInput];
    }
    for (TUCTouch *touch in self.touchSet.allObjects) {
        if (touch.locationID == locationID) [self.touchSet removeObject:touch];
    }
    if (self.activeTouches.count == 0) self.waitingForAllTouchesToLift = NO;
    if (self.previousDrawingTapDevice == locationID) self.hasPreviousDrawingTap = NO;
    [self.delegate touchesDidChange];
    [self.frameIDsByLocationID removeObjectForKey:@(locationID)];
    [self.delegate touchscreenDidDisconnectWithLocationID:locationID];
}



#pragma mark - Reacting to HID Events

- (NSInteger)currentFrameIDForLocationID:(uint32_t)locationID {
    return self.frameIDsByLocationID[@(locationID)].integerValue;
}

- (void)didProcessReportForLocationID:(uint32_t)locationID {
    // go through all touches: if the frame is not the latest one, the touch might be old and should be removed.
    NSInteger currentFrameID = [self currentFrameIDForLocationID:locationID];

    for (TUCTouch *touch in self.touchSet) {
        if (touch.locationID != locationID) continue;

        if (touch.lastUpdated + self.errorResistance < currentFrameID) {
            [touch setPhase:NSTouchPhaseCancelled];
            if (touch == self.drawingTouch) [self finishDrawingTouchCancelled:YES];
            [self removeTouch:touch now:NO];
        }
    }

    if ([[self activeTouches] count] == 0) {
        self.waitingForAllTouchesToLift = NO;
        if (!self.drawingModeEnabled) [self stopCurrentGesture];
    }

    self.frameIDsByLocationID[@(locationID)] = @(currentFrameID + 1);

    [self processTouchesForCursorInput];

}


- (void)stopCurrentGesture {
    [self.cursorUtilities stopDraggingCursor];
    [self.cursorUtilities stopMagnifying];

    self.identifiedMultitouchGesture = _TUCCursorGestureNone;
}



/**
 Most important event handling callback: it posts the events to the system where the touches need to go
 */
- (void)updateTouch:(NSInteger)contactID locationID:(uint32_t)locationID withLocation:(CGPoint)digitizerPoint onSurface:(BOOL)isOnSurface tooLargeForFinger:(BOOL)confidenceFlag {
    
    // assume that this is an erroneous message!!!
    if (self.ignoreOriginTouches && CGPointEqualToPoint(digitizerPoint, CGPointZero)) {
        // Liftoff reports sometimes contain no position. Still release at the last good point.
        if (isOnSurface || !self.drawingModeEnabled) return;
        TUCTouch *existing = [self findTouchWithID:contactID locationID:locationID includingPastTouches:NO];
        if (!existing) return;
        existing.isOnSurface = NO;
        existing.phase = NSTouchPhaseEnded;
        if (existing == self.drawingTouch) [self finishDrawingTouchCancelled:NO];
        [self removeTouch:existing now:NO];
        [self.delegate touchesDidChange];
        return;
    }
    if (self.drawingModeEnabled && !isOnSurface &&
        ![self findTouchWithID:contactID locationID:locationID includingPastTouches:NO]) return;
    
    CGPoint point = [self convertDigitizerPointToRelativeScreenPoint:digitizerPoint locationID:locationID];
    
    BOOL isNewTouch = NO;
    TUCTouch *touch = [self obtainTouchWithID:contactID locationID:locationID isNew:&isNewTouch];
    
    if (isNewTouch && (self.cursorTouch == nil || !self.cursorTouch.isActive)) {
        self.cursorTouch = touch;
        self.cursorTouchQualifiedForTap = YES;
        self.cursorTouchDidHold = NO;
        self.cursorTouchStationarySinceDate = nil;
    }
    
    [touch setLocation: point];
    [touch setIsOnSurface:isOnSurface];
    [touch setConfidenceFlag:confidenceFlag];
    [touch setLastUpdated:[self currentFrameIDForLocationID:locationID]];
    
    if (!isOnSurface) {
        [touch setPhase: NSTouchPhaseEnded];
        if (touch == self.drawingTouch) {
            [self updateDrawingLocation:touch];
            [self finishDrawingTouchCancelled:NO];
        }
        [self removeTouch:touch now:NO];
        [self.delegate touchesDidChange];
        return;
        
    }
    
    if(touch.previousPhase != NSTouchPhaseEnded && !isNewTouch) {
        // update to an existing touch... check if stationary or not.
        // Convert each axis to mm first (x scales with the panel width, y with its height),
        // then take the distance — otherwise a non-square screen distorts the threshold per axis.
        CGSize physicalSize = [self touchscreenForLocationID:locationID].nativePhysicalSize;
        CGFloat dxMM = (touch.location.x - touch.previousLocation.x) * physicalSize.width;
        CGFloat dyMM = (touch.location.y - touch.previousLocation.y) * physicalSize.height;
        CGFloat movedDistanceMM = sqrt(dxMM * dxMM + dyMM * dyMM);
        BOOL isStationary = movedDistanceMM < self.stationaryThreshold;
        
        if (touch.uuid == self.cursorTouch.uuid) {
            if (!isStationary) {
                self.cursorTouchQualifiedForTap = NO;
                self.cursorTouchStationarySinceDate = nil;
                
            } else if (touch.phase !=  NSTouchPhaseStationary) {
                self.cursorTouchStationarySinceDate = [NSDate date];
            }
        }
        
        [touch setPhase:isStationary ? NSTouchPhaseStationary : NSTouchPhaseMoved];
    }
    
    
    if (self.drawingModeEnabled) [self processDrawingTouch:touch isNew:isNewTouch];
    [self.delegate touchesDidChange];
    
    return;
}


- (void)updateTouch:(NSInteger)contactID locationID:(uint32_t)locationID withSize:(CGSize)size azimuth:(CGFloat)azimuth {
    BOOL isNewTouch = NO;
    TUCTouch *touch = [self obtainTouchWithID:contactID locationID:locationID isNew:&isNewTouch];
    [touch setLastUpdated:[self currentFrameIDForLocationID:locationID]];
    
    [touch setSize:size];
    [touch setAzimuth:azimuth];
}



#pragma mark - Immediate Drawing Input

- (void)setDrawingModeEnabled:(BOOL)enabled {
    if (_drawingModeEnabled == enabled) return;
    [self cancelCurrentInput];
    _drawingModeEnabled = enabled;
}

- (void)setPostMouseEvents:(BOOL)enabled {
    if (_postMouseEvents == enabled) return;
    [self cancelCurrentInput];
    _postMouseEvents = enabled;
}

- (void)cancelCurrentInput {
    [self finishDrawingTouchCancelled:YES];
    [self stopCurrentGesture];
    [self.cursorUtilities cancelMomentumScroll];
    self.cursorTouch = nil;
    self.gestureAdditionalTouch = nil;
    self.hasPreviousDrawingTap = NO;
    self.waitingForAllTouchesToLift = self.activeTouches.count > 0;
}

- (NSTimeInterval)inputTime {
    return NSProcessInfo.processInfo.systemUptime;
}

- (CGFloat)drawingDistanceFrom:(CGPoint)a to:(CGPoint)b device:(uint32_t)device {
    CGSize size = [self touchscreenForLocationID:device].nativePhysicalSize;
    // Without panel dimensions, only identical points can safely qualify as nearby.
    if (!isfinite(size.width) || !isfinite(size.height) || size.width <= 0 || size.height <= 0) {
        return CGPointEqualToPoint(a, b) ? 0 : CGFLOAT_MAX;
    }
    return hypot((a.x - b.x) * size.width, (a.y - b.y) * size.height);
}

- (void)processDrawingTouch:(TUCTouch *)touch isNew:(BOOL)isNew {
    if (!self.postMouseEvents || self.waitingForAllTouchesToLift) return;
    if (self.drawingTouch) {
        if (touch == self.drawingTouch) [self updateDrawingLocation:touch];
        return;
    }
    if (!isNew || !touch.isOnSurface || ![self touchscreenForLocationID:touch.locationID]) return;
    self.drawingTouch = touch;
    self.drawingStartLocation = touch.location;
    self.drawingStartTime = [self inputTime];
    self.drawingQualifiedForTap = YES;
    NSTimeInterval interval = self.drawingStartTime - self.previousDrawingTapTime;
    BOOL isNextClick = self.hasPreviousDrawingTap &&
        self.previousDrawingTapDevice == touch.locationID &&
        interval >= 0 && interval <= NSEvent.doubleClickInterval &&
        [self drawingDistanceFrom:touch.location to:self.previousDrawingTapLocation device:touch.locationID] <= self.doubleClickTolerance;
    self.drawingClickCount = isNextClick ? self.previousDrawingTapCount % 3 + 1 : 1;
    self.hasPreviousDrawingTap = NO;
    self.drawingLastLocation = [self clampScreenPointRelativeToAbsolute:touch.location locationID:touch.locationID];
    [self.cursorUtilities beginDrawingAt:self.drawingLastLocation clickCount:self.drawingClickCount];
}

- (void)updateDrawingLocation:(TUCTouch *)touch {
    if (![self touchscreenForLocationID:touch.locationID]) {
        [self cancelCurrentInput];
        return;
    }
    // Cumulative movement prevents a slow stroke from being mistaken for a tap.
    if ([self drawingDistanceFrom:touch.location to:self.drawingStartLocation device:touch.locationID] > MAX(0.5, self.stationaryThreshold)) {
        self.drawingQualifiedForTap = NO;
    }
    CGPoint location = [self clampScreenPointRelativeToAbsolute:touch.location locationID:touch.locationID];
    if (!CGPointEqualToPoint(location, self.drawingLastLocation)) {
        [self.cursorUtilities continueDrawingAt:location];
        self.drawingLastLocation = location;
    }
}

- (void)finishDrawingTouchCancelled:(BOOL)cancelled {
    if (!self.drawingTouch) return;
    [self.cursorUtilities endDrawingAt:self.drawingLastLocation];
    self.hasPreviousDrawingTap = !cancelled && self.drawingQualifiedForTap &&
        [self inputTime] - self.drawingStartTime <= NSEvent.doubleClickInterval;
    self.previousDrawingTapLocation = self.drawingStartLocation;
    self.previousDrawingTapDevice = self.drawingTouch.locationID;
    self.previousDrawingTapTime = self.drawingStartTime;
    self.previousDrawingTapCount = self.drawingClickCount;
    self.drawingTouch = nil;
    // Do not promote an extra finger, including a new contact later in this HID report.
    self.waitingForAllTouchesToLift = YES;
}

#pragma mark - Mouse Cursor Management



- (void)processTouchesForCursorInput {
    
    if(self.drawingModeEnabled || self.waitingForAllTouchesToLift || !self.cursorTouch || !self.postMouseEvents) {
        return;
    }
    
    TUCTouch *cursorTouch = self.cursorTouch;
    
    
    NSArray<TUCTouch *> *touches = [[self activeTouches] allObjects];
    NSTouchPhase phase = cursorTouch.phase;
    
    
    if (phase == NSTouchPhaseBegan) {
        [self performMouseEventForGesture:TUCCursorGestureTouchDown];
        return;
    }
    
    
    else if (phase == NSTouchPhaseStationary) {
        NSTimeInterval holdDuration = 0;
        if (self.cursorTouchStationarySinceDate != nil) {
            holdDuration = [[NSDate date] timeIntervalSinceDate:self.cursorTouchStationarySinceDate];
        }
        if (self.cursorTouchQualifiedForTap && holdDuration > self.holdDuration) {
            // the user left the finger on the screen for the min duration required to produce a hold
            self.cursorTouchDidHold = YES;
        }
        
        [self checkForSecondaryClick];
        
        return;
    }
    
    
    else if (phase == NSTouchPhaseEnded) {
        if (self.identifiedMultitouchGesture == _TUCCursorGestureNone ) {
            if (self.cursorTouchDidHold) {
                [self performMouseEventForGesture:TUCCursorGestureHoldAndDrag];
            } else if (!self.cursorTouchQualifiedForTap) {
                [self performMouseEventForGesture:TUCCursorGestureDrag];
            }
        }
        
        [self stopCurrentGesture];
        
        if (self.cursorTouchQualifiedForTap) {
            [self performMouseEventForGesture:TUCCursorGestureTap];
        } else {
            if (self.identifiedMultitouchGesture != _TUCCursorGestureNone) {
                [self performMouseEventForGesture:self.identifiedMultitouchGesture];
            }
        }
        
        return;
    }
    
    
    else if (phase == NSTouchPhaseCancelled) {
        [self stopCurrentGesture];
        return;
    }
    
    if ([self checkForSecondaryClick]) {
        return;
    }
    
    if ([touches count] == 2 && [touches containsObject: cursorTouch]) {
        // check if we need to initiate two finger drag, pinch, ...
        if (self.identifiedMultitouchGesture == _TUCCursorGestureNone ) {
            
            TUCTouch *otherTouch = touches[1];
            if (otherTouch.uuid == cursorTouch.uuid) {
                otherTouch = touches[0];
            }
            
            self.gestureAdditionalTouch = otherTouch;
            
            if (self.gestureAdditionalTouch.isActive) {
                CGPoint trajectoryA = [cursorTouch trajectorySign];
                CGPoint trajectoryB = [otherTouch trajectorySign];
                
                
                if (   !CGPointEqualToPoint(trajectoryA, CGPointZero)
                    && !CGPointEqualToPoint(trajectoryB, CGPointZero)) {
                    
                    if (!CGPointEqualToPoint(trajectoryA, trajectoryB)) {
                        self.identifiedMultitouchGesture = TUCCursorGesturePinch;
                    }
                    //                    else {
                    //                        self.identifiedMultitouchGesture = TUCCursorGestureTwoFingerDrag;
                    //                    }
                }
                
            } else {
                // secondary click
                [self removeTouch:self.gestureAdditionalTouch now:YES];
                self.gestureAdditionalTouch = nil;
                [self performMouseEventForGesture:TUCCursorGestureTapSecondFinger];
            }
        }
        
        // other finger lifted, gesture ended
        if (!self.gestureAdditionalTouch.isActive) {
            [self stopCurrentGesture];
        }
        
        
        if(self.identifiedMultitouchGesture != _TUCCursorGestureNone) {
            [self performMouseEventForGesture:self.identifiedMultitouchGesture];
            return;
        }
        
    }
    
    
    if (self.cursorTouchDidHold) {
        [self performMouseEventForGesture:TUCCursorGestureHoldAndDrag];
    } else {
        [self performMouseEventForGesture:TUCCursorGestureDrag];
    }
}


- (BOOL)checkForSecondaryClick {
    //    if (self.identifiedMultitouchGesture != _TUCCursorGestureNone) {
    //        return NO;
    //    }
    
    NSSet<TUCTouch *> *touchesInProximity = [self touchesInProximityTo:self.cursorTouch.location maxDistance:60 locationID:self.cursorTouch.locationID];
    if (touchesInProximity.count >= 2 && self.identifiedMultitouchGesture == _TUCCursorGestureNone) {
        
        // TUCCursorGestureTwoFingerTap
        NSPredicate *p1 = [NSPredicate predicateWithFormat:@"phase == %d", NSTouchPhaseEnded];
        NSPredicate *p2 = [NSPredicate predicateWithFormat:@"phase == %d", NSTouchPhaseCancelled];
        
        NSPredicate *p3 = [NSPredicate predicateWithFormat:@"contactID != %d", self.cursorTouch.contactID];
        
        NSPredicate *p4 = [NSCompoundPredicate orPredicateWithSubpredicates:@[p1, p2]];
        NSPredicate *p5 = [NSCompoundPredicate andPredicateWithSubpredicates:@[p3, p4]];
        
        NSSet<TUCTouch *> *endedTouches = [touchesInProximity filteredSetUsingPredicate:p5];
        
        if (endedTouches.count == 1) {
            for (TUCTouch* touchToRemove in endedTouches) {
                [self removeTouch:touchToRemove now:YES];
            }
            
            [self performMouseEventForGesture:TUCCursorGestureTapSecondFinger];
            return YES;
        }
    }
    return NO;
}


- (void)performMouseEventForGesture:(TUCCursorGesture)gesture {
    TUCTouch *touch = self.cursorTouch;
    
    CGPoint screenLocation = [self clampScreenPointRelativeToAbsolute:touch.location locationID:touch.locationID];
    CGPoint location2ndFinger = [self clampScreenPointRelativeToAbsolute:self.gestureAdditionalTouch.location locationID:touch.locationID];
    
    TUCCursorUtilities *utils = self.cursorUtilities;
    
    TUCCursorAction action = [self actionForGesture:gesture];
    
    CGFloat doubleClickSpan = self.doubleClickTolerance * [[self touchscreenForLocationID:touch.locationID] pixelsPerMM];
    [self.cursorUtilities setDoubleClickTolerance:doubleClickSpan];
    
    switch (action) {
        case TUCCursorActionNone:
            break;
            
        case TUCCursorActionMove:
            [utils moveCursorTo:screenLocation];
            break;
            
        case TUCCursorActionMoveClickIfNeeded:
            [utils moveCursorTo:screenLocation];
            if ([self isLocationOutsideFrontmostWindow:screenLocation locationID:touch.locationID]) {
                [utils performClickAt:screenLocation];
            }
            
            break;
            
        case TUCCursorActionPointAndClick:
            [utils moveCursorTo:screenLocation];
            if (touch.phase == NSTouchPhaseEnded) {
                [utils performClickAt:screenLocation];
            }
            break;
            
        case TUCCursorActionDrag:
            [utils dragCursorTo:screenLocation phase:touch.phase];
            break;
            
        case TUCCursorActionClick:
            [utils performClickAt:screenLocation];
            break;
            
        case TUCCursorActionSecondaryClick:
            [utils performSecondaryClickAt: screenLocation];
            break;
            
        case TUCCursorActionScroll: {
            CGPoint prevLocation = [self clampScreenPointRelativeToAbsolute:touch.previousLocation locationID:touch.locationID];
            CGPoint translation = CGPointMake(screenLocation.x - prevLocation.x,
                                              screenLocation.y - prevLocation.y);
            [utils scroll:translation phase:touch.phase];
            
            break; }
            
        case TUCCursorActionMagnify:
            [utils magnifyLocationA:screenLocation
                          locationB:location2ndFinger
                         relativeP1:self.cursorTouch.location relP2:self.gestureAdditionalTouch.location];
            
            if (touch.phase == NSTouchPhaseEnded || self.gestureAdditionalTouch.phase == NSTouchPhaseEnded) {
                [utils stopMagnifying];
            }
            break;
    }
}


- (TUCCursorAction)actionForGesture:(TUCCursorGesture)gesture {
    
    if (self.delegate != nil) {
        return [self.delegate actionForGesture:gesture];
    }
    
    switch(gesture) {
        case TUCCursorGestureTouchDown:         return TUCCursorActionMoveClickIfNeeded;
        case TUCCursorGestureTap:               return TUCCursorActionClick;
        case TUCCursorGestureLongPress:         return TUCCursorActionClick;
        case TUCCursorGestureDrag:              return TUCCursorActionScroll;
        case TUCCursorGestureHoldAndDrag:       return TUCCursorActionDrag;
        case TUCCursorGestureTapSecondFinger:   return TUCCursorActionSecondaryClick;
        case TUCCursorGestureTwoFingerDrag:     return TUCCursorActionDrag;
            
        case TUCCursorGesturePinch:             return TUCCursorActionMagnify;
        case _TUCCursorGestureNone:             return TUCCursorActionNone;
    }
}


#pragma mark - Touch Set

/**
 The `touchSet` can contain touches whose phase is ended or cancelled. activeTouches. filteres those out
 */
- (NSSet<TUCTouch *> *)activeTouches {
    NSPredicate *p1 = [NSPredicate predicateWithFormat:@"phase != %d", NSTouchPhaseEnded];
    NSPredicate *p2 = [NSPredicate predicateWithFormat:@"phase != %d", NSTouchPhaseCancelled];
    
    NSPredicate *predicate = [NSCompoundPredicate andPredicateWithSubpredicates:@[p1, p2]];
    
    return [self.touchSet filteredSetUsingPredicate:predicate];
}



- (CGFloat)distanceBetweenPoint:(CGPoint)p1 and:(CGPoint)p2 {
    CGFloat dx = p1.x - p2.x;
    CGFloat dy = p1.y - p2.y;
    
    return sqrt( pow(dx, 2) + pow(dy, 2) );
}


/**
 maxDistance in mm
 */
- (NSSet<TUCTouch *> *)touchesInProximityTo:(CGPoint)point maxDistance:(CGFloat)mmDistance locationID:(uint32_t)locationID {
    
    TUCScreen *screen = [self touchscreenForLocationID:locationID];
    CGFloat screenDistance = mmDistance * [screen pixelsPerMM];
    CGPoint distance = CGPointMake(screenDistance / screen.frame.size.width,
                                   screenDistance / screen.frame.size.height);
    
    NSPredicate * predicate = [NSPredicate predicateWithBlock: ^BOOL(TUCTouch *t, NSDictionary *bind) {
        if (t.locationID != locationID) return NO;

        CGFloat dx = [t location].x - point.x;
        CGFloat dy = [t location].y - point.y;

        return sqrt( pow(dx, 2) + pow(dy, 2) ) < distance.x;
    }];
    
    return [self.touchSet filteredSetUsingPredicate:predicate];
}


/**
 Removes a touch from the touch set. As a previous touch might be important for gesture evaluation, it is removed after half a second
 */
- (void)removeTouch:(TUCTouch *)touch now:(BOOL)instantDeletion{
    //    if (touch.uuid == self.touchUsedForCursor.uuid) {
    //        [self processTouchesForCursorInput];
    //        self.touchUsedForCursor = nil;
    //    }
    
    if (instantDeletion) {
        [[self touchSet] removeObject:touch];
        [[self delegate] touchesDidChange];
        return;
    }
    
    __weak id weakSelf = self;
    NSUUID *uuid = touch.uuid;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), dispatch_get_main_queue(), ^{
        for(TUCTouch *touch in [weakSelf touchSet]) {
            if (touch.uuid == uuid && [[weakSelf touchSet] containsObject:touch]) {
                [[weakSelf touchSet] removeObject:touch];
                [[weakSelf delegate] touchesDidChange];
                return;
            }
        }
    });
}


/**
 Checks the touch set if a touch exists
 */
- (TUCTouch *)findTouchWithID:(NSInteger)contactID locationID:(uint32_t)locationID includingPastTouches:(BOOL)includePastTouches {
    NSSet *set = includePastTouches ? self.touchSet : [self activeTouches];
    
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"contactID == %d AND locationID == %u", contactID, locationID];
    TUCTouch *touch = [[set filteredSetUsingPredicate:predicate] anyObject];
    return touch;
}

/**
 Returns the existing touch object or a new one if this ID does not exist in the set yet.
 */
- (TUCTouch *)obtainTouchWithID:(NSInteger)contactID locationID:(uint32_t)locationID isNew:(BOOL*)isNew {
    TUCTouch *touch = [self findTouchWithID:contactID locationID:locationID includingPastTouches:NO];
    *isNew = NO;
    if(!touch) {
        touch = [[TUCTouch alloc] initWithContactID:contactID locationID:locationID];
        [self.touchSet addObject:touch];
        *isNew = YES;
    }
    return touch;
}





#pragma mark - Screen Characteristics

/**
 the relative hardware points are always in the direction the digitizer is built in.
 If the display is rotated, we need to rotate these points
 */
- (CGPoint)convertDigitizerPointToRelativeScreenPoint:(CGPoint)devicePoint locationID:(uint32_t)locationID {
    TUCScreen *screen = [self touchscreenForLocationID:locationID];

    CGFloat rotation = screen.rotation;

    CGFloat extra = [[self delegate] digitizerRotationForLocationID:locationID];

    rotation += extra;
    rotation = fmod(rotation, 360);
    if (rotation < 0) {
        rotation += 360;
    }

    // Rotate the glass-relative point into the screen's content orientation.
    CGPoint rotated;
    if (rotation == 180) {
        rotated = CGPointMake(1 - devicePoint.x, 1 - devicePoint.y);
    } else if (rotation == 90) {
        rotated = CGPointMake(1 - devicePoint.y, devicePoint.x);
    } else if (rotation == 270) {
        rotated = CGPointMake(devicePoint.y, 1 - devicePoint.x);
    } else {
        rotated = devicePoint;
    }

    // Then account for any letterboxing when the content doesn't fill the panel (mirroring
    // a differently-shaped display). A no-op when the aspect ratios already match.
    return [screen convertGlassPointToContentPoint:rotated];
}



- (CGPoint)convertScreenPointRelativeToAbsolute:(CGPoint)relativePoint locationID:(uint32_t)locationID {
    return [[self touchscreenForLocationID:locationID] convertPointRelativeToAbsolute:relativePoint];
}



- (CGPoint)clampScreenPointRelativeToAbsolute:(CGPoint)relativePoint locationID:(uint32_t)locationID {
    TUCScreen *screen = [self touchscreenForLocationID:locationID];
    CGPoint clamped = [screen clampRelativePoint:relativePoint toEdgeInset:self.edgeDeadZone];
    return [screen convertPointRelativeToAbsolute:clamped];
}



- (TUCScreen *)touchscreenForLocationID:(uint32_t)locationID {
    if (self.delegate != nil) {
        return [self.delegate touchscreenForLocationID:locationID];
    }
    
    return [[TUCScreen allScreens] firstObject];
}



- (BOOL)isPointInMenuBar:(CGPoint)point locationID:(uint32_t)locationID {
    CGFloat menuBarHeight = [[[NSApplication sharedApplication] mainMenu] menuBarHeight];
    
    CGRect screenFrame = [self touchscreenForLocationID:locationID].frame;
    CGRect menuBarFrame = CGRectMake(screenFrame.origin.x,
                                     screenFrame.origin.y * -1,
                                     screenFrame.size.width,
                                     menuBarHeight);
    
    if (CGRectContainsPoint(menuBarFrame, point)) {
        return YES;
    }
    return NO;
}


- (BOOL)isSystemChromeOwner:(pid_t)pid name:(NSString *)ownerName {
    static NSSet<NSString *> *chromeBundleIDs;
    static NSSet<NSString *> *chromeOwnerNames;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        chromeBundleIDs = [NSSet setWithArray:@[
            @"com.apple.dock",
            @"com.apple.controlcenter",
            @"com.apple.notificationcenterui",
        ]];
        // The Window Server has no NSRunningApplication, so match it by owner name.
        chromeOwnerNames = [NSSet setWithArray:@[ @"Window Server", @"WindowServer" ]];
    });

    if (ownerName && [chromeOwnerNames containsObject:ownerName]) {
        return YES;
    }

    NSString *bundleID = [NSRunningApplication runningApplicationWithProcessIdentifier:pid].bundleIdentifier;
    return bundleID != nil && [chromeBundleIDs containsObject:bundleID];
}


- (BOOL)isLocationOutsideFrontmostWindow:(CGPoint)point locationID:(uint32_t)locationID {

    if ([self isPointInMenuBar:point locationID:locationID]) {
        return NO;
    }

    pid_t frontmostPID = [[[NSWorkspace sharedWorkspace] frontmostApplication] processIdentifier];

    CFArrayRef array = CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly|kCGWindowListExcludeDesktopElements, kCGNullWindowID);

    // The window list is ordered front-to-back by window *level* (not grouped by app), so
    // high-level overlays — including our own screenSaver-level panels — come before the
    // active app's normal windows. `behindFrontmostWindow` flips once we pass the active
    // app's topmost window: windows seen before it are stacked above it, windows after are
    // behind it.
    BOOL behindFrontmostWindow = NO;
    BOOL res = NO;

    for (CFIndex i=0; i<CFArrayGetCount(array); i++) {
        CFDictionaryRef dic = CFArrayGetValueAtIndex(array, i);

        CFNumberRef numPid = CFDictionaryGetValue(dic, kCGWindowOwnerPID);
        pid_t currPID;
        CFNumberGetValue(numPid, kCFNumberIntType,  &currPID);
        BOOL isFrontmostApp = currPID == frontmostPID;

        CFDictionaryRef bounds = CFDictionaryGetValue(dic, kCGWindowBounds);
        CGRect nextFrame;
        CGRectMakeWithDictionaryRepresentation(bounds, &nextFrame);
        BOOL isInside = CGRectContainsPoint(nextFrame, point);

        if (isFrontmostApp && !behindFrontmostWindow) {
            behindFrontmostWindow = YES;
        }

        if (!isInside) continue;

        NSString *ownerName = (__bridge NSString *)CFDictionaryGetValue(dic, kCGWindowOwnerName);
        if ([self isSystemChromeOwner:currPID name:ownerName]) {
            continue;
        }

        // First real window under the point = the one the finger actually hits.
        if (isFrontmostApp) {
            res = NO;   // already the active window — the tap actuates it directly
        } else if (!behindFrontmostWindow) {
            res = NO;   // stacked above the active app (an overlay or our own panel) — takes the tap directly
        } else {
            // A background window of another app — normally inject a click to raise it.
            // Exception: the title bar. A background title bar accepts clicks directly, so
            // our injected raise-click plus the tap's own click would register as a
            // title-bar double-click (→ zoom/fullscreen). A single tap already raises the
            // window, so skip the extra click within the title-bar strip.
            //
            // CGWindowList can't tell us the actual title-bar/toolbar height, so this is a
            // heuristic constant. Erring high (toolbars on Tahoe are tall) costs at most a
            // missed raise-click near the top of a background window; erring low brings the
            // destructive double-click-zoom back.
            CGFloat titleBarHeight = 44;
            BOOL inTitleBar = (point.y - nextFrame.origin.y) <= titleBarHeight;
            res = inTitleBar ? NO : YES;
        }
        break;
    }

    CFRelease(array);
    return res;
}





#pragma mark -

- (instancetype)init {
    return [self initWithCursorUtilities:[TUCCursorUtilities sharedInstance]];
}

- (instancetype)initWithCursorUtilities:(TUCCursorUtilities *)utilities {
    if(self = [super init]) {
        self.cursorUtilities = utilities;
        self.touchSet = [NSMutableSet new];
        _postMouseEvents = YES;
        
        self.cursorTouchQualifiedForTap = NO;
        self.cursorTouchStationarySinceDate = nil;
        
        self.frameIDsByLocationID = [NSMutableDictionary new];
        self.identifiedMultitouchGesture = _TUCCursorGestureNone;
        
        self.doubleClickTolerance = 5;
        self.holdDuration = 0.08;
        self.stationaryThreshold = 0.1;
        self.edgeDeadZone = 0;
        self.errorResistance = 0;
        
        self.ignoreOriginTouches = NO;
    }
    return self;
}


- (void)dealloc {
    [self stop];
}

- (NSString *)debugDescription {
    NSMutableString *str = [[NSString stringWithFormat:@"Touch Set contains %ld touches:{\n", [self.touchSet count]] mutableCopy];
    
    for (TUCTouch *touch in [[self.touchSet allObjects] sortedArrayUsingSelector:@selector(compareWithAnotherTouch:)] ) {
        [str appendString: [NSString stringWithFormat:@"  %@", [touch debugDescription]] ];
        if (touch.contactID == self.cursorTouch.contactID) {
            [str appendString: @" <<<CURSOR>>>\n" ];
        } else {
            [str appendString: @"\n" ];
        }
    }
    
    [str appendString:@"}"];
    return str;
}

- (void)triggerSystemAccessibilityAccessAlert {
    CGPoint loc = [self.cursorUtilities currentCursorLocation];
    [self.cursorUtilities moveCursorTo:loc];
}



#pragma mark - Bridge calls of C Header to Objective-C

void TouchInputManagerUpdateTouchPosition(void *self, uint32_t locationID, CFIndex contactID, CGFloat x, CGFloat y, Boolean onSurface, Boolean isValid) {
    CGPoint point = CGPointMake(x, y);
    [(__bridge id)self updateTouch:(NSInteger)contactID locationID:locationID withLocation:point onSurface:onSurface tooLargeForFinger:isValid];
}

void TouchInputManagerUpdateTouchSize(void *self, uint32_t locationID, CFIndex contactID, CGFloat width, CGFloat height, CGFloat azimuth) {
    CGSize size = CGSizeMake(width, height);
    [(__bridge id)self updateTouch:(NSInteger)contactID locationID:locationID withSize:size azimuth:azimuth];
}

void TouchInputManagerDidProcessReport(void *self, uint32_t locationID) {
    [(__bridge id)self didProcessReportForLocationID:locationID];
}

void TouchInputManagerDidConnectTouchscreen(void *self, uint32_t locationID) {
    [(__bridge id)self didConnectTouchscreenWithLocationID:locationID];
}

void TouchInputManagerDidDisconnectTouchscreen(void *self, uint32_t locationID) {
    [(__bridge id)self didDisconnectTouchscreenWithLocationID:locationID];
}


@end
