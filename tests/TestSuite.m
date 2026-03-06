#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>

// Mock infra

#define MAX_POSTED_EVENTS 128
static int gPostedEventCount = 0;
static CGKeyCode gPostedKeys[MAX_POSTED_EVENTS];
static CGEventFlags gPostedFlags[MAX_POSTED_EVENTS];
static bool gPostedIsDown[MAX_POSTED_EVENTS];

// Mock for CGEventPost to capture events instead of sending them to the system
void mock_CGEventPost(CGEventTapLocation tap, CGEventRef event) {
    if (gPostedEventCount < MAX_POSTED_EVENTS) {
        gPostedKeys[gPostedEventCount] = (CGKeyCode)CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
        gPostedFlags[gPostedEventCount] = CGEventGetFlags(event);
        
        CGEventType type = CGEventGetType(event);
        gPostedIsDown[gPostedEventCount] = (type == kCGEventKeyDown);
        
        gPostedEventCount++;
    }
}

// Mock for NSWorkspace to control the active application during tests
@interface MockWorkspace : NSObject
+ (instancetype)sharedWorkspace;
- (id)frontmostApplication;
@end

static NSString *gMockBundleID = nil;

@interface MockApp : NSObject
- (NSString *)bundleIdentifier;
@end

@implementation MockApp
- (NSString *)bundleIdentifier { return gMockBundleID; }
@end

@implementation MockWorkspace
+ (instancetype)sharedWorkspace { static MockWorkspace *s; return s ?: (s = [MockWorkspace new]); }
- (id)frontmostApplication { return [MockApp new]; }
@end

// Inject mocks before including the source
#define CGEventPost mock_CGEventPost
#define NSWorkspace MockWorkspace
#define usleep(x) (void)0  // prevent tests from waiting during screenshot/UI simulations
#define main app_main
#include "../src/McWinning.m"
#undef main
#undef usleep
#undef NSWorkspace
#undef CGEventPost

// Test runner infra

static int gTotalTests = 0;
static int gPassedTests = 0;
static BOOL gCurrentTestFailed = NO;

#define ASSERT(cond) \
    if (!(cond)) { \
        printf("\n  [!] ASSERTION FAILED: %s (at %s:%d)\n", #cond, __FILE__, __LINE__); \
        gCurrentTestFailed = YES; \
        return; \
    }

void run_test(void (*test_func)(void), const char *name) {
    gTotalTests++;
    gCurrentTestFailed = NO;
    printf("[%02d] Running %-30s ", gTotalTests, name);
    fflush(stdout);
    
    test_func();
    
    if (!gCurrentTestFailed) {
        gPassedTests++;
        printf("PASSED\n");
    } else {
        printf("FAILED\n");
    }
}

#define RUN_TEST(func) run_test(func, #func)

// Test utils

void reset_mocks() {
    gPostedEventCount = 0;
    memset(gPostedKeys, 0, sizeof(gPostedKeys));
    memset(gPostedFlags, 0, sizeof(gPostedFlags));
    memset(gPostedIsDown, 0, sizeof(gPostedIsDown));
    gMockBundleID = nil;
    for (int i = 0; i < 256; i++) gIgnoreKeyUp[i] = false;
    gAltTabActive = false;
}

bool wasKeyPosted(CGKeyCode key) {
    for (int i = 0; i < gPostedEventCount; i++) {
        if (gPostedKeys[i] == key) return true;
    }
    return false;
}

bool wasKeyPostedWithFlags(CGKeyCode key, CGEventFlags flags) {
    for (int i = 0; i < gPostedEventCount; i++) {
        if (gPostedKeys[i] == key && (gPostedFlags[i] & flags) == flags) return true;
    }
    return false;
}

CGEventRef createKeyEvent(CGKeyCode key, bool down, CGEventFlags flags) {
    CGEventSourceRef src = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    CGEventRef e = CGEventCreateKeyboardEvent(src, key, down);
    CGEventSetFlags(e, flags);
    CFRelease(src);
    return e;
}

// Test cases

void test_terminal_shortcuts() {
    reset_mocks();
    gMockBundleID = @"com.apple.Terminal";
    
    CGEventRef e = createKeyEvent(kKeyC, true, kCGEventFlagMaskControl | kCGEventFlagMaskShift);
    CGEventRef result = eventCallback(NULL, kCGEventKeyDown, e, NULL);
    
    ASSERT(result == NULL);
    ASSERT(gPostedEventCount > 0);
    ASSERT(wasKeyPosted(kKeyC));
    ASSERT(wasKeyPosted(kKeyCmd));
    ASSERT(wasKeyPostedWithFlags(kKeyC, kCGEventFlagMaskCommand));
    
    result = eventCallback(NULL, kCGEventKeyUp, e, NULL);
    ASSERT(result == NULL);
    
    CFRelease(e);
}

void test_browser_shortcuts() {
    reset_mocks();
    gMockBundleID = @"com.google.Chrome";
    
    CGEventRef e = createKeyEvent(kKeyF5, true, 0);
    CGEventRef result = eventCallback(NULL, kCGEventKeyDown, e, NULL);
    ASSERT(result == NULL);
    ASSERT(wasKeyPosted(kKeyR));
    ASSERT(wasKeyPostedWithFlags(kKeyR, kCGEventFlagMaskCommand));
    CFRelease(e);
    
    reset_mocks();
    gMockBundleID = @"com.google.Chrome";
    e = createKeyEvent(kKeyJ, true, kCGEventFlagMaskControl);
    result = eventCallback(NULL, kCGEventKeyDown, e, NULL);
    ASSERT(result == NULL);
    ASSERT(wasKeyPosted(kKeyL));
    ASSERT(wasKeyPostedWithFlags(kKeyL, kCGEventFlagMaskCommand | kCGEventFlagMaskAlternate));
    CFRelease(e);
}

void test_finder_shortcuts() {
    reset_mocks();
    gMockBundleID = @"com.apple.finder";
    
    CGEventRef e = createKeyEvent(kKeyBackspace, true, 0);
    CGEventRef result = eventCallback(NULL, kCGEventKeyDown, e, NULL);
    ASSERT(result == NULL);
    ASSERT(wasKeyPosted(kKeyUp));
    ASSERT(wasKeyPostedWithFlags(kKeyUp, kCGEventFlagMaskCommand));
    CFRelease(e);
    
    reset_mocks();
    gMockBundleID = @"com.apple.finder";
    e = createKeyEvent(kKeyEnter, true, kCGEventFlagMaskAlternate);
    result = eventCallback(NULL, kCGEventKeyDown, e, NULL);
    ASSERT(result == NULL);
    ASSERT(wasKeyPosted(kKeyI));
    ASSERT(wasKeyPostedWithFlags(kKeyI, kCGEventFlagMaskCommand));
    CFRelease(e);
}

void test_generic_shortcuts() {
    reset_mocks();
    gMockBundleID = @"com.apple.Notes"; 
    
    CGEventRef e = createKeyEvent(kKeyS, true, kCGEventFlagMaskControl);
    CGEventRef result = eventCallback(NULL, kCGEventKeyDown, e, NULL);
    ASSERT(result == NULL);
    ASSERT(wasKeyPosted(kKeyS));
    ASSERT(wasKeyPostedWithFlags(kKeyS, kCGEventFlagMaskCommand));
    CFRelease(e);
}

void test_screenshots() {
    reset_mocks();
    
    CGEventRef e = createKeyEvent(kKeyPrintScreen, true, 0);
    CGEventRef result = eventCallback(NULL, kCGEventKeyDown, e, NULL);
    ASSERT(result == NULL);
    ASSERT(wasKeyPosted(kKey4));
    ASSERT(wasKeyPostedWithFlags(kKey4, kCGEventFlagMaskCommand | kCGEventFlagMaskShift));
    CFRelease(e);
}

void test_global_hotkeys() {
    reset_mocks();
    
    CGEventRef e = createKeyEvent(kKeyEsc, true, kCGEventFlagMaskControl);
    CGEventRef result = eventCallback(NULL, kCGEventKeyDown, e, NULL);
    ASSERT(result == NULL);
    ASSERT(wasKeyPosted(kKeySpace));
    ASSERT(wasKeyPostedWithFlags(kKeySpace, kCGEventFlagMaskCommand));
    CFRelease(e);
}

void test_own_event_ignored() {
    reset_mocks();
    
    CGEventRef e = createKeyEvent(kKeyC, true, kCGEventFlagMaskControl);
    CGEventSetIntegerValueField(e, kCGEventSourceUserData, MAGIC_NUMBER);
    
    CGEventRef result = eventCallback(NULL, kCGEventKeyDown, e, NULL);
    ASSERT(result == e);
    ASSERT(gPostedEventCount == 0);
    CFRelease(e);
}

void test_navigation_shortcuts() {
    reset_mocks();
    
    CGEventRef e = createKeyEvent(kKeyEnd, true, 0);
    CGEventRef result = eventCallback(NULL, kCGEventKeyDown, e, NULL);
    ASSERT(result == NULL);
    ASSERT(wasKeyPosted(kKeyRight));
    ASSERT(wasKeyPostedWithFlags(kKeyRight, kCGEventFlagMaskCommand));
    CFRelease(e);
}

void test_alt_tab() {
    reset_mocks();
    
    CGEventRef e = createKeyEvent(kKeyTab, true, kCGEventFlagMaskAlternate);
    CGEventRef result = eventCallback(NULL, kCGEventKeyDown, e, NULL);
    ASSERT(result != NULL);
    CGEventFlags flags = CGEventGetFlags(result);
    ASSERT(flags & kCGEventFlagMaskCommand);
    ASSERT(!(flags & kCGEventFlagMaskAlternate));
    ASSERT(gAltTabActive == true);
    CFRelease(e);
}

void test_app_detection() {
    reset_mocks();
    
    ASSERT(isTerminal(@"com.apple.Terminal") == YES);
    ASSERT(isTerminal(@"com.googlecode.iterm2") == YES);
    ASSERT(isTerminal(@"com.apple.Safari") == NO);
    
    ASSERT(isBrowser(@"com.google.Chrome") == YES);
    ASSERT(isBrowser(@"com.apple.Safari") == YES);
    ASSERT(isBrowser(@"org.mozilla.firefox") == YES);
    ASSERT(isBrowser(@"com.apple.Terminal") == NO);
    
    ASSERT(isFinder(@"com.apple.finder") == YES);
    ASSERT(isFinder(@"com.apple.Terminal") == NO);
}

int main(int argc, char *argv[]) {
    (void)argc; (void)argv;
    @autoreleasepool {
        RUN_TEST(test_terminal_shortcuts);
        RUN_TEST(test_browser_shortcuts);
        RUN_TEST(test_finder_shortcuts);
        RUN_TEST(test_generic_shortcuts);
        RUN_TEST(test_screenshots);
        RUN_TEST(test_global_hotkeys);
        RUN_TEST(test_own_event_ignored);
        RUN_TEST(test_navigation_shortcuts);
        RUN_TEST(test_alt_tab);
        RUN_TEST(test_app_detection);
        printf("Summary: %d/%d Tests passed!\n", gPassedTests, gTotalTests);
    }
    
    return (gPassedTests == gTotalTests) ? 0 : 1;
}
