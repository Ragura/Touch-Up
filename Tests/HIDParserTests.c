#include <IOKit/hid/IOHIDManager.h>
#include <IOKit/hidsystem/IOHIDLib.h>
#include <assert.h>
#include <limits.h>

// Synthetic HID objects at the IOKit boundary; the production parser and Core
// Foundation ownership/lookup behavior run unchanged. No USB or events are used.
typedef struct { uint32_t mockCookie, mockPage, mockUsage; CFIndex min, max; CFArrayRef mockChildren; } Element;
typedef struct { Element *element; CFIndex value; } Value;
static IOHIDElementCookie mockCookie(IOHIDElementRef e) { return ((Element *)e)->mockCookie; }
static uint32_t mockPage(IOHIDElementRef e) { return ((Element *)e)->mockPage; }
static uint32_t mockUsage(IOHIDElementRef e) { return ((Element *)e)->mockUsage; }
static CFIndex mockMinimum(IOHIDElementRef e) { return ((Element *)e)->min; }
static CFIndex mockMaximum(IOHIDElementRef e) { return ((Element *)e)->max; }
static CFArrayRef mockChildren(IOHIDElementRef e) { return ((Element *)e)->mockChildren; }
static IOHIDElementRef mockValueElement(IOHIDValueRef v) { return (IOHIDElementRef)((Value *)v)->element; }
static CFIndex mockIntegerValue(IOHIDValueRef v) { return ((Value *)v)->value; }
#define IOHIDElementGetCookie mockCookie
#define IOHIDElementGetUsagePage mockPage
#define IOHIDElementGetUsage mockUsage
#define IOHIDElementGetLogicalMin mockMinimum
#define IOHIDElementGetLogicalMax mockMaximum
#define IOHIDElementGetChildren mockChildren
#define IOHIDValueGetElement mockValueElement
#define IOHIDValueGetIntegerValue mockIntegerValue
#include "../TouchUpCore/HIDInterpreter.c"

static int updates, reports;
static CGFloat lastX, lastY;
static Boolean lastDown;
void TouchInputManagerUpdateTouchPosition(void *m, uint32_t l, CFIndex c, CGFloat x, CGFloat y, Boolean s, Boolean v) {
    updates++; lastX = x; lastY = y; lastDown = s;
}
void TouchInputManagerUpdateTouchSize(void *m, uint32_t l, CFIndex c, CGFloat w, CGFloat h, CGFloat a) {}
void TouchInputManagerDidProcessReport(void *m, uint32_t l) { reports++; }
void TouchInputManagerDidConnectTouchscreen(void *m, uint32_t l) {}
void TouchInputManagerDidDisconnectTouchscreen(void *m, uint32_t l) {}
static void store(HIDDeviceState *d, Element *e, CFIndex n) {
    Value v = { e, n }; StoreInputValue(d, (IOHIDValueRef)&v);
}
int main(void) {
    int identity;
    HIDDeviceState *d = AllocateDeviceState((IOHIDDeviceRef)&identity, 1);
    Element x = {1001, kHIDPage_GenericDesktop, kHIDUsage_GD_X, 0, 1000};
    Element y = {1002, kHIDPage_GenericDesktop, kHIDUsage_GD_Y, -100, 100};
    Element tip = {1003, kHIDPage_Digitizer, kHIDUsage_Dig_TipSwitch};
    Element count = {1004, kHIDPage_Digitizer, kHIDUsage_Dig_ContactCount};
    Element large = {1005, kHIDPage_Digitizer, kHIDUsage_Dig_ContactIdentifier};
    // Heap-backed CFNumbers must survive the parser releasing its temporary refs.
    store(d, &large, LONG_MAX);
    for (int i = 0; i < 1000; i++) {
        store(d, &x, i);
        assert(ValueOfElement(d, (IOHIDElementRef)&large) == LONG_MAX);
        assert(ValueOfElement(d, (IOHIDElementRef)&x) == i);
    }
    assert(CFDictionaryGetCount(d->storedInputValues) == 2);
    const void *items[] = {&x, &y, &tip};
    Element collection = {0};
    collection.mockChildren = CFArrayCreate(NULL, items, 3, NULL);
    store(d, &x, 250); store(d, &y, 0); store(d, &tip, 1);
    DispatchTouchDataForCollection(d, (IOHIDElementRef)&collection);
    assert(updates == 1 && lastX == .25 && lastY == .5 && lastDown);
    store(d, &x, 500);
    DispatchTouchDataForCollection(d, (IOHIDElementRef)&collection);
    assert(updates == 2 && lastX == .5 && lastDown);
    store(d, &tip, 0);
    DispatchTouchDataForCollection(d, (IOHIDElementRef)&collection);
    assert(updates == 3 && !lastDown);
    // Invalid descriptor, reversed range, out-of-range value, and invalid tip.
    x.max = x.min;
    DispatchTouchDataForCollection(d, (IOHIDElementRef)&collection);
    x.max = -1;
    DispatchTouchDataForCollection(d, (IOHIDElementRef)&collection);
    x.max = 1000; store(d, &x, 1001);
    DispatchTouchDataForCollection(d, (IOHIDElementRef)&collection);
    store(d, &x, -1);
    DispatchTouchDataForCollection(d, (IOHIDElementRef)&collection);
    store(d, &x, 500); store(d, &tip, 2);
    DispatchTouchDataForCollection(d, (IOHIDElementRef)&collection);
    assert(updates == 3);
    CFRelease(collection.mockChildren); collection.mockChildren = NULL;
    DispatchTouchDataForCollection(d, (IOHIDElementRef)&collection);
    assert(updates == 3);
    // Reject extreme counts without overflow; finish the report so stale touches
    // can be cancelled by the manager rather than leaving a button held forever.
    store(d, &count, LONG_MAX); DispatchTouches(d);
    store(d, &count, -1); DispatchTouches(d);
    assert(reports == 2 && d->contactCount == 0 && d->hybridOffset == 0);
    // Preserve valid hybrid reports: three contacts delivered in groups of two.
    CFRelease(d->touchCollectionElements);
    d->touchCollectionElements = CFArrayCreateMutable(NULL, 0, NULL);
    CFArrayAppendValue(d->touchCollectionElements, &collection);
    CFArrayAppendValue(d->touchCollectionElements, &collection);
    store(d, &count, 3); DispatchTouches(d);
    assert(d->hybridOffset == 2 && reports == 2);
    store(d, &count, 0); DispatchTouches(d);
    assert(d->hybridOffset == 0 && reports == 3);
    store(d, &count, 257); DispatchTouches(d);
    assert(d->contactCount == 0 && reports == 4);
    DeallocateDeviceState((IOHIDDeviceRef)&identity);
    assert(gDeviceCount == 0);
    puts("PASS: HID storage ownership, repeated lookup, down/move/up, coordinate validation, empty collections and invalid counts.");
}
