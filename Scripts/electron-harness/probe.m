// The Electron harness's probe (main.js), inserted into its Electron at launch (DYLD_INSERT_LIBRARIES; the pinned
// Electron is signed without the hardened runtime): logs what reaches the input method, and drives the harness's own
// window with a script of key events, posted to its own event queue as the system delivers them. Nothing goes to any
// other app.
//
// What reaches the input method: a key down through the text input context (-[NSTextInputContext handleEvent:], from
// interpretKeyEvents:), a modifier change through TSMProcessRawKeyEvent, which -[NSApplication sendEvent:] calls for it
// (unless the first responder's input context is asynchronous: WebKit's). Chromium sends a key event the page didn't
// handle through -[NSApplication sendEvent:] again (-[CommandDispatcher redispatchKeyEvent:], its window key), so the
// input method gets every modifier change twice.
//
// Environment: HARNESS_SCRIPT (shift-hold, shift-tap, shift-letter), HARNESS_DELAY (seconds before it starts, the page
// loaded), HARNESS_FAKE_KEY (the window says it's key, as it is while someone types in it: on a locked screen, or with
// another app in front, no app becomes active; it's what Chromium looks at before it sends an event again). Prints
// "REC <seconds into the script> <what> …" lines on stdout for the self-test (ElectronSelfTest.swift), and what it sees
// on stderr; quits once the script is done.
//
// Built by `make electron-harness`:
//   clang -dynamiclib -fobjc-arc -framework AppKit -framework Carbon -o libprobe.dylib probe.m
#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#import <execinfo.h>
#import <objc/runtime.h>

extern OSStatus TSMProcessRawKeyEvent(EventRef event);

static double up(void) { return NSProcessInfo.processInfo.systemUptime; }

static void say(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static void say(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    fprintf(stderr, "[probe %.3f] %s\n", up(), line.UTF8String);
}

/// When the script started (0: not yet; nothing is recorded before).
static double scriptStart = 0;

/// One line for the self-test: what reached the input method (or what the probe did), seconds into the script.
static void record(NSString *what) {
    if (scriptStart == 0) return;
    fprintf(stdout, "REC %.4f %s\n", up() - scriptStart, what.UTF8String);
    fflush(stdout);
}

static NSString *typeName(NSEvent *e) {
    switch (e.type) {
    case NSEventTypeKeyDown: return @"keyDown";
    case NSEventTypeKeyUp: return @"keyUp";
    case NSEventTypeFlagsChanged: return @"flagsChanged";
    default: return [NSString stringWithFormat:@"type%lu", (unsigned long)e.type];
    }
}

static NSString *describe(NSEvent *e) {
    NSString *chars = e.type == NSEventTypeFlagsChanged ? @"" : [NSString stringWithFormat:@" chars=%@", e.characters];
    return [NSString stringWithFormat:@"%@ code=%u flags=0x%lx%@ ts=%.3f", typeName(e), e.keyCode,
            (unsigned long)e.modifierFlags, chars, e.timestamp];
}

/// "<type> <keyCode> <flags> <timestamp, seconds into the script>[ <characters, percent-encoded>]".
static NSString *recorded(NSEvent *e) {
    NSString *line = [NSString stringWithFormat:@"%@ %u 0x%lx %.4f", typeName(e), e.keyCode, (unsigned long)e.modifierFlags,
                      e.timestamp - scriptStart];
    if (e.type == NSEventTypeFlagsChanged) return line;
    NSString *chars = [e.characters stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.alphanumericCharacterSet];
    return [line stringByAppendingFormat:@" %@", chars];
}

static BOOL isKey(NSEvent *e) {
    return e.type == NSEventTypeKeyDown || e.type == NSEventTypeKeyUp || e.type == NSEventTypeFlagsChanged;
}

/// Where a call came from: a few frames, their symbols only.
static NSString *caller(int count) {
    void *frames[16];
    int n = backtrace(frames, 16);
    char **symbols = backtrace_symbols(frames, n);
    NSMutableArray *parts = [NSMutableArray array];
    for (int i = 2; i < n && i < 2 + count; i++) {
        NSString *s = @(symbols[i]);
        NSRange address = [s rangeOfString:@" 0x"];
        if (address.location != NSNotFound) {
            NSRange space = [s rangeOfString:@" " options:0 range:NSMakeRange(address.location + 1, s.length - address.location - 1)];
            if (space.location != NSNotFound) s = [s substringFromIndex:space.location + 1];
        }
        [parts addObject:s];
    }
    free(symbols);
    return [parts componentsJoinedByString:@" < "];
}

static void swizzle(Class cls, SEL sel, IMP replacement, IMP *original) {
    Method m = cls ? class_getInstanceMethod(cls, sel) : NULL;
    if (!m) {
        say(@"no %@ on %@", NSStringFromSelector(sel), NSStringFromClass(cls));
        return;
    }
    *original = method_setImplementation(m, replacement);
}

// MARK: What reaches the input method

static OSStatus probeTSMProcessRawKeyEvent(EventRef event) {
    NSEvent *e = [NSEvent eventWithEventRef:event];
    say(@"TSMProcessRawKeyEvent %@ < %@", describe(e), caller(4));
    if (e.type == NSEventTypeFlagsChanged) record(recorded(e));
    return TSMProcessRawKeyEvent(event);
}
__attribute__((used, section("__DATA,__interpose"))) static struct {
    const void *replacement, *original;
} interposeTSM = {(const void *)probeTSMProcessRawKeyEvent, (const void *)TSMProcessRawKeyEvent};

static IMP originalHandleEvent, originalActivate, originalDeactivate;

static BOOL probeHandleEvent(NSTextInputContext *self, SEL _cmd, NSEvent *e) {
    say(@"-[NSTextInputContext handleEvent:] %@ < %@", describe(e), caller(3));
    // A key down reaches the input method here. With the context not active (no app is, the screen locked) it goes
    // no further: recorded as the input method would get it.
    if (e.type == NSEventTypeKeyDown) record(recorded(e));
    return ((BOOL (*)(id, SEL, NSEvent *))originalHandleEvent)(self, _cmd, e);
}

static void probeActivate(NSTextInputContext *self, SEL _cmd) {
    say(@"-[NSTextInputContext activate] < %@", caller(4));
    record(@"activate");
    ((void (*)(id, SEL))originalActivate)(self, _cmd);
}

static void probeDeactivate(NSTextInputContext *self, SEL _cmd) {
    say(@"-[NSTextInputContext deactivate] < %@", caller(4));
    record(@"deactivate");
    ((void (*)(id, SEL))originalDeactivate)(self, _cmd);
}

// MARK: Chromium sending an event again

static IMP originalRedispatch, originalAppSendEvent;

static BOOL probeRedispatch(id self, SEL _cmd, NSEvent *e) {
    say(@"-[CommandDispatcher redispatchKeyEvent:] %@", describe(e));
    return ((BOOL (*)(id, SEL, NSEvent *))originalRedispatch)(self, _cmd, e);
}

static void probeAppSendEvent(NSApplication *self, SEL _cmd, NSEvent *e) {
    if (isKey(e)) say(@"-[NSApplication sendEvent:] %@", describe(e));
    ((void (*)(id, SEL, NSEvent *))originalAppSendEvent)(self, _cmd, e);
}

// MARK: The window said to be key

static IMP originalIsKeyWindow;

static BOOL probeIsKeyWindow(NSWindow *self, SEL _cmd) {
    if ([self isKindOfClass:NSClassFromString(@"ElectronNSWindow")]) return YES;
    return ((BOOL (*)(id, SEL))originalIsKeyWindow)(self, _cmd);
}

// MARK: The script

static NSWindow *harnessWindow(void) {
    for (NSWindow *w in NSApp.windows)
        if ([w isKindOfClass:NSClassFromString(@"ElectronNSWindow")]) return w;
    return NSApp.windows.firstObject;
}

/// Into the app's own event queue, for its window: as the system delivers a key.
static void post(NSEvent *e) {
    record([NSString stringWithFormat:@"posted %@ %u 0x%lx", typeName(e), e.keyCode, (unsigned long)e.modifierFlags]);
    say(@"posted %@", describe(e));
    [NSApp postEvent:e atStart:NO];
}

// Left Shift: key code 56, NSEventModifierFlagShift with NX_DEVICELSHIFTKEYMASK (0x2); 0x100 is NX_NONCOALSESCEDMASK.
static const NSEventModifierFlags leftShift = NSEventModifierFlagShift | 0x2 | 0x100;
static const NSEventModifierFlags noModifier = 0x100;

static NSEvent *keyEvent(NSEventType type, NSEventModifierFlags flags, unsigned short code, NSString *characters) {
    return [NSEvent keyEventWithType:type location:NSZeroPoint modifierFlags:flags timestamp:up()
                        windowNumber:harnessWindow().windowNumber context:nil characters:characters
         charactersIgnoringModifiers:characters.lowercaseString isARepeat:NO keyCode:code];
}

/// Steps: seconds after the step before, then what it does.
static NSArray *steps(NSString *name) {
    void (^shiftDown)(void) = ^{ post(keyEvent(NSEventTypeFlagsChanged, leftShift, 56, @"")); };
    void (^shiftUp)(void) = ^{ post(keyEvent(NSEventTypeFlagsChanged, noModifier, 56, @"")); };
    if ([name isEqualToString:@"shift-hold"]) return @[@[@0, shiftDown], @[@1.28, shiftUp]];
    if ([name isEqualToString:@"shift-tap"]) return @[@[@0, shiftDown], @[@0.1, shiftUp]];
    if ([name isEqualToString:@"shift-letter"]) {
        return @[@[@0, shiftDown], @[@0.2, ^{ post(keyEvent(NSEventTypeKeyDown, leftShift, 0, @"A")); }],
                 @[@0.05, ^{ post(keyEvent(NSEventTypeKeyUp, leftShift, 0, @"A")); }], @[@1.0, shiftUp]];
    }
    return nil;
}

static void run(NSArray *script, NSUInteger index) {
    if (index >= script.count) {
        // What comes after the last step (an event sent again) has half a second to arrive.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            record(@"end");
            say(@"script done");
            exit(0);
        });
        return;
    }
    NSArray *step = script[index];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)([step[0] doubleValue] * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        ((void (^)(void))step[1])();
        run(script, index + 1);
    });
}

__attribute__((constructor)) static void start(void) {
    // Inserted at launch, Electron's helpers (renderer, GPU …) load it too: only the app itself is probed.
    if (![NSBundle.mainBundle.bundlePath hasSuffix:@"/Electron.app"]) return;
    swizzle([NSTextInputContext class], @selector(handleEvent:), (IMP)probeHandleEvent, &originalHandleEvent);
    swizzle([NSTextInputContext class], @selector(activate), (IMP)probeActivate, &originalActivate);
    swizzle([NSTextInputContext class], @selector(deactivate), (IMP)probeDeactivate, &originalDeactivate);
    swizzle([NSApplication class], @selector(sendEvent:), (IMP)probeAppSendEvent, &originalAppSendEvent);
    // Chromium's classes are in its framework, loaded with the app.
    swizzle(NSClassFromString(@"CommandDispatcher"), NSSelectorFromString(@"redispatchKeyEvent:"), (IMP)probeRedispatch,
            &originalRedispatch);
    NSDictionary *environment = NSProcessInfo.processInfo.environment;
    if (environment[@"HARNESS_FAKE_KEY"])
        swizzle([NSWindow class], @selector(isKeyWindow), (IMP)probeIsKeyWindow, &originalIsKeyWindow);
    [NSWorkspace.sharedWorkspace.notificationCenter addObserverForName:NSWorkspaceDidActivateApplicationNotification
                                                                object:nil queue:nil usingBlock:^(NSNotification *note) {
        NSRunningApplication *app = note.userInfo[NSWorkspaceApplicationKey];
        say(@"another app active: %@", app.bundleIdentifier);
        record([NSString stringWithFormat:@"appActivated %@", app.bundleIdentifier]);
    }];
    NSString *name = environment[@"HARNESS_SCRIPT"];
    NSArray *script = steps(name);
    if (!script) return;
    double delay = [environment[@"HARNESS_DELAY"] ?: @"3" doubleValue];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        scriptStart = up();
        record([NSString stringWithFormat:@"script %@ %@", name, NSBundle.mainBundle.bundleIdentifier]);
        run(script, 0);
    });
}
