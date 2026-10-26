#include <IOKit/hid/IOHIDManager.h>
#include <IOKit/hidsystem/IOHIDLib.h>
#include <assert.h>

static int attempts;
static IOHIDQueueRef failQueue(CFAllocatorRef allocator, IOHIDDeviceRef device, CFIndex depth, IOOptionBits options) {
    attempts++;
    return NULL;
}
static IOHIDAccessType deniedAccess(IOHIDRequestType request) { return kIOHIDAccessTypeDenied; }
#define IOHIDQueueCreate failQueue
#define IOHIDCheckAccess deniedAccess
#include "../TouchUpCore/HIDInterpreter.c"

void TouchInputManagerUpdateTouchPosition(void *m, uint32_t l, CFIndex c, CGFloat x, CGFloat y, Boolean s, Boolean v) {}
void TouchInputManagerUpdateTouchSize(void *m, uint32_t l, CFIndex c, CGFloat w, CGFloat h, CGFloat a) {}
void TouchInputManagerDidProcessReport(void *m, uint32_t l) {}
void TouchInputManagerDidConnectTouchscreen(void *m, uint32_t l) { assert(!"failed device must not connect"); }
void TouchInputManagerDidDisconnectTouchscreen(void *m, uint32_t l) {}

int main(void) {
    // Inject failure at the OS queue boundary. The pre-fix path crashes here.
    int identity;
    IOHIDDeviceRef device = (IOHIDDeviceRef)&identity;
    for (int i = 0; i < 8; i++) {
        assert(RegisterTouchDevice(device, 1234, 10) == NULL);
        assert(gDeviceCount == 0);
        assert(DeviceStateForRef(device) == NULL);
        assert(RegisteredDeviceForLocationID(1234) == NULL);
    }
    assert(attempts == 8);
    CloseHIDManager();
    CloseHIDManager();
    puts("PASS: failed HID queues do not crash, leak registration slots, or publish devices; repeated close is safe.");
}
