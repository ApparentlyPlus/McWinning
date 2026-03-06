/*
 * McWinning.m
 * A small utility that remaps Windows-like shortcuts into macOS ones.
 *
 * The general idea is simple: intercept keyboard events using CGEventTap and
 * translate them. I mostly wrote this because constantly switching between
 * Windows and macOS shortcuts was annoying. Also, I quite adamantly dislike macOS.
 * 
 * Author: u/ApparentlyPlus
 */

#import <ApplicationServices/ApplicationServices.h>
#import <Cocoa/Cocoa.h>

// used to mark events we inject ourselves
#define MAGIC_NUMBER 0xDEADBEEF  

// small delay when doing window screenshots (macOS UI needs usually a moment)
static const int64_t kDelayWindowSelection = 50000;  // ~50ms

// Keycodes, from google/hid and other sources. Only the ones we care about.
typedef enum {
  kKeyA = 0,
  kKeyS = 1,
  kKeyD = 2,
  kKeyF = 3,
  kKeyH = 4,
  kKeyG = 5,
  kKeyZ = 6,
  kKeyX = 7,
  kKeyC = 8,
  kKeyV = 9,
  kKeyB = 11,
  kKeyQ = 12,
  kKeyW = 13,
  kKeyE = 14,
  kKeyR = 15,
  kKeyY = 16,
  kKeyT = 17,
  kKey1 = 18,
  kKey2 = 19,
  kKey3 = 20,
  kKey4 = 21,
  kKey6 = 22,
  kKey5 = 23,
  kKey9 = 25,
  kKey7 = 26,
  kKey8 = 28,
  kKey0 = 29,
  kKeyO = 31,
  kKeyU = 32,
  kKeyI = 34,
  kKeyP = 35,
  kKeyL = 37,
  kKeyJ = 38,
  kKeyK = 40,
  kKeyN = 45,
  kKeyM = 46,
  kKeyTab = 48,
  kKeySpace = 49,
  kKeyBacktick = 50,
  kKeyBackspace = 51,
  kKeyEsc = 53,
  kKeyCmd = 55,
  kKeyShift = 56,
  kKeyAlt = 58,
  kKeyCtrl = 59,
  kKeyF5 = 96,
  kKeyPrintScreen = 105,
  kKeyHome = 115,
  kKeyDelete = 117,
  kKeyF4 = 118,
  kKeyEnd = 119,
  kKeyF2 = 120,
  kKeyLeft = 123,
  kKeyRight = 124,
  kKeyDown = 125,
  kKeyUp = 126,
  kKeyEnter = 36,
  kKeySlash = 44
} KeyCode;

// Global state
static CFMachPortRef gEventTap = NULL;

// Sometimes we inject events and want to ignore the matching KeyUp
static bool gIgnoreKeyUp[256] = {false};

// Alt-tab handling state
static bool gAltTabActive = false;


// Simple wrapper around CGEventCreateKeyboardEvent.
// Mostly here because... convenience?
void postKeyEvent(CGEventSourceRef source, CGKeyCode key, bool isDown, CGEventFlags flags) {
  CGEventRef e = CGEventCreateKeyboardEvent(source, key, isDown);

  if (flags != 0) {
    CGEventSetFlags(e, flags);
  }

  // mark it so we don't process our own injected events later
  CGEventSetIntegerValueField(e, kCGEventSourceUserData, MAGIC_NUMBER);

  CGEventPost(kCGHIDEventTap, e);
  CFRelease(e);
}

// Simulates Cmd + key (optionally with shift).
// This is slightly verbose but mimics real key presses more closely
void performCommandKey(int keycode, BOOL withShift) {
  CGEventSourceRef src = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
  if (!src) return;

  CGEventFlags flags = kCGEventFlagMaskCommand;

  if (withShift) {
    flags |= kCGEventFlagMaskShift;
  }

  // press modifiers manually
  postKeyEvent(src, kKeyCmd, true, 0);

  if (withShift) postKeyEvent(src, kKeyShift, true, 0);

  postKeyEvent(src, (CGKeyCode)keycode, true, flags);
  postKeyEvent(src, (CGKeyCode)keycode, false, flags);

  if (withShift) postKeyEvent(src, kKeyShift, false, 0);

  postKeyEvent(src, kKeyCmd, false, 0);

  CFRelease(src);
}

// Screenshot helper
// macOS screenshot shortcuts are a bit weird so this handles the variations.
void performScreenshot(BOOL altHeld, BOOL shiftHeld) {
  CGEventSourceRef src = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);

  // Cmd + Shift is always part of the combo
  CGEventFlags flags = kCGEventFlagMaskCommand | kCGEventFlagMaskShift;

  int key = shiftHeld ? kKey3 : kKey4;

  postKeyEvent(src, (CGKeyCode)key, true, flags);
  postKeyEvent(src, (CGKeyCode)key, false, flags);

  // If Alt was used we switch to window-selection mode
  if (altHeld && !shiftHeld) {
    // might not need this delay but macOS UI seemed flaky without it
    usleep(kDelayWindowSelection);

    postKeyEvent(src, kKeySpace, true, 0);
    postKeyEvent(src, kKeySpace, false, 0);
  }

  CFRelease(src);
}

// helper for combos like Cmd+Alt+Key
void performCombo(int mod1, int mod2, int key) {
  CGEventSourceRef src = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);

  CGEventFlags flags = kCGEventFlagMaskCommand | kCGEventFlagMaskAlternate;

  postKeyEvent(src, (CGKeyCode)mod1, true, 0);
  postKeyEvent(src, (CGKeyCode)mod2, true, 0);

  postKeyEvent(src, (CGKeyCode)key, true, flags);
  postKeyEvent(src, (CGKeyCode)key, false, flags);

  postKeyEvent(src, (CGKeyCode)mod2, false, 0);
  postKeyEvent(src, (CGKeyCode)mod1, false, 0);

  CFRelease(src);
}

// crude detection but works well enough for my use cases, feel fre to PR
BOOL isTerminal(NSString *bundle) {
  return [bundle isEqualToString:@"com.apple.Terminal"] ||
         [bundle isEqualToString:@"com.googlecode.iterm2"] ||
         [bundle isEqualToString:@"io.alacritty"] ||
         [bundle isEqualToString:@"net.kovidgoyal.kitty"] ||
         [bundle isEqualToString:@"com.github.wez.wezterm"];
}

// same deal
BOOL isBrowser(NSString *bundle) {
  return
      [bundle containsString:@"Chrome"] || [bundle containsString:@"Safari"] ||
      [bundle containsString:@"firefox"] || [bundle containsString:@"Brave"] ||
      [bundle containsString:@"edgemac"] || [bundle containsString:@"Opera"] ||
      [bundle containsString:@"Vivaldi"];
}

BOOL isFinder(NSString *bundle) {
  return [bundle isEqualToString:@"com.apple.finder"];
}

// Application specific handlers

CGEventRef handleTerminal(CGEventRef event, int64_t keycode, BOOL ctrl, BOOL shift) {
  if (ctrl && shift) {
    // typical terminal actions people expect from Windows
    switch (keycode) {
      case kKeyC:
      case kKeyV:
      case kKeyA:
      case kKeyF:
      case kKeyN:
      case kKeyT:
      case kKeyW:

        performCommandKey((int)keycode, NO);
        gIgnoreKeyUp[keycode] = true;
        return NULL;
    }
  }

  return event;
}

CGEventRef handleBrowser(CGEventRef event, int64_t keycode, BOOL ctrl, BOOL shift, BOOL alt) {
  // refresh logic
  if (keycode == kKeyF5) {
    performCommandKey(kKeyR, ctrl);  // ctrl+F5 = hard reload
    return NULL;
  }

  if (ctrl) {
    if (keycode == kKeyL || keycode == kKeyT || keycode == kKeyN ||
        keycode == kKeyR || keycode == kKeyW || keycode == kKeyH ||
        (keycode >= kKey1 && keycode <= kKey9)) {
      int mapped = (keycode == kKeyH) ? kKeyY : (int)keycode;

      performCommandKey(mapped, shift);
      gIgnoreKeyUp[keycode] = true;

      return NULL;
    }

    // downloads
    if (keycode == kKeyJ) {
      performCombo(kKeyCmd, kKeyAlt, kKeyL);
      gIgnoreKeyUp[keycode] = true;
      return NULL;
    }
  }

  if (alt && (keycode == kKeyLeft || keycode == kKeyRight)) {
    performCommandKey((int)keycode, NO);
    gIgnoreKeyUp[keycode] = true;
    return NULL;
  }

  return event;
}

CGEventRef handleFinder(CGEventRef event, int64_t keycode, BOOL ctrl, BOOL cmd, BOOL alt) {
  if (keycode == kKeyDelete) {
    performCommandKey(kKeyBackspace, NO);
    gIgnoreKeyUp[keycode] = true;
    return NULL;
  }

  if (keycode == kKeyEnter && !ctrl && !cmd && !alt) {
    performCommandKey(kKeyO, NO);  // open file
    gIgnoreKeyUp[keycode] = true;
    return NULL;
  }

  if (alt && keycode == kKeyEnter) {
    performCommandKey(kKeyI, NO);  // file info
    gIgnoreKeyUp[keycode] = true;
    return NULL;
  }

  if (keycode == kKeyBackspace && !ctrl && !cmd) {
    performCommandKey(kKeyUp, NO);
    gIgnoreKeyUp[keycode] = true;
    return NULL;
  }

  if (ctrl && keycode == kKeyA) {
    performCommandKey(kKeyA, NO);
    gIgnoreKeyUp[keycode] = true;
    return NULL;
  }

  return event;
}

// Main event callback
CGEventRef eventCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon) {
  // recover from tap timeouts
  if (type == kCGEventTapDisabledByTimeout ||
      type == kCGEventTapDisabledByUserInput) {
    CGEventTapEnable(gEventTap, true);
    return event;
  }

  // ignore our own injected events
  if (CGEventGetIntegerValueField(event, kCGEventSourceUserData) ==
      MAGIC_NUMBER)
    return event;

  int64_t keycode = CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
  CGEventFlags flags = CGEventGetFlags(event);

  BOOL ctrl = (flags & kCGEventFlagMaskControl) != 0;
  BOOL alt = (flags & kCGEventFlagMaskAlternate) != 0;
  BOOL cmd = (flags & kCGEventFlagMaskCommand) != 0;
  BOOL shift = (flags & kCGEventFlagMaskShift) != 0;

  // Alt+Tab translation
  if (type == kCGEventKeyDown && alt && keycode == kKeyTab) {
    gAltTabActive = true;

    CGEventSetFlags(
        event, (flags & ~kCGEventFlagMaskAlternate) | kCGEventFlagMaskCommand);

    return event;
  }

  if (type == kCGEventFlagsChanged) {
    if (!(flags & kCGEventFlagMaskAlternate) && gAltTabActive)
      gAltTabActive = false;
  }

  if (gAltTabActive) return event;

  // ignore keyup from injected events
  if (type == kCGEventKeyUp) {
    if (keycode < 256 && gIgnoreKeyUp[keycode]) {
      gIgnoreKeyUp[keycode] = false;
      return NULL;
    }

    return event;
  }

  if (type != kCGEventKeyDown) return event;

  // global hotkeys

  if (keycode == kKeyPrintScreen) {
    performScreenshot(alt, shift);
    return NULL;
  }

  if (ctrl && keycode == kKeyEsc) {
    performCommandKey(kKeySpace, NO);
    gIgnoreKeyUp[keycode] = true;
    return NULL;
  }

  // Application specific behavior
  @autoreleasepool {
    NSRunningApplication *front = [[NSWorkspace sharedWorkspace] frontmostApplication];
    NSString *bundleID = [front bundleIdentifier];

    if (isTerminal(bundleID)) {
      CGEventRef r = handleTerminal(event, keycode, ctrl, shift);
      if (!r) return NULL;
    } else if (isBrowser(bundleID)) {
      CGEventRef r = handleBrowser(event, keycode, ctrl, shift, alt);
      if (!r) return NULL;
    } else if (isFinder(bundleID)) {
      CGEventRef r = handleFinder(event, keycode, ctrl, cmd, alt);
      if (!r) return NULL;
    }

    // generic windows-style ctrl shortcuts
    if (!isTerminal(bundleID) && ctrl && !cmd) {
      BOOL handled = NO;

      switch (keycode) {
        case kKeyA:
        case kKeyC:
        case kKeyV:
        case kKeyX:
        case kKeyZ:
        case kKeyS:
        case kKeyO:
        case kKeyN:
        case kKeyW:
        case kKeyF:
        case kKeyP:
        case kKeyT:
        case kKeyL:
        case kKeyR:
        case kKeyK:
        case kKeyB:
        case kKeyI:
        case kKeyU:
        case kKeySlash:
        case kKeyEnter:

          performCommandKey((int)keycode, shift);
          gIgnoreKeyUp[keycode] = true;
          handled = YES;
          break;
      }

      if (handled) return NULL;
    }
  }

  // Home / End navigation
  if (keycode == kKeyHome || keycode == kKeyEnd) {
    int mapped = (keycode == kKeyHome) ? kKeyLeft : kKeyRight;

    if (ctrl) mapped = (keycode == kKeyHome) ? kKeyUp : kKeyDown;

    performCommandKey(mapped, shift);

    gIgnoreKeyUp[keycode] = true;
    return NULL;
  }

  // Close window shortcuts
  if ((alt || ctrl) && keycode == kKeyF4) {
    performCommandKey((alt ? kKeyQ : kKeyW), NO);
    gIgnoreKeyUp[keycode] = true;
    return NULL;
  }

  return event;
}

int main(void) {
  @autoreleasepool {
    CGEventMask mask = CGEventMaskBit(kCGEventKeyDown) | CGEventMaskBit(kCGEventKeyUp) | CGEventMaskBit(kCGEventFlagsChanged);

    gEventTap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault, mask, eventCallback, NULL);

    if (!gEventTap) {
      fprintf(stderr, "Failed to create event tap. Did you enable "
                      "Accessibility permissions?\n");
      return 1;
    }

    CFRunLoopSourceRef src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, gEventTap, 0);

    CFRunLoopAddSource(CFRunLoopGetCurrent(), src, kCFRunLoopCommonModes);

    CGEventTapEnable(gEventTap, true);

    printf("WinMacSwapper running...\n");

    // main loop
    CFRunLoopRun();
  }

  return 0;
}