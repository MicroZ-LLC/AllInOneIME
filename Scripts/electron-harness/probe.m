// The Electron harness's probe (main.js), inserted into its Electron at launch (DYLD_INSERT_LIBRARIES; the pinned
// Electron is signed without the hardened runtime): logs what reaches the input method, and drives the harness's own
// window with a script of key events, posted to its own event queue as the system delivers them. Nothing goes to any
// other app.
//
// What reaches the input method: a key down through the text input context (-[NSTextInputContext handleEvent:], from
// interpretKeyEvents:), a modifier change through TSMProcessRawKeyEvent, which -[NSApplication sendEvent:] calls for it
// (unless the first responder's input context is asynchronous: WebKit's). Chromium sends a key event the page didn't
// handle through -[NSApplication sendEvent:] again (-[CommandDispatcher redispatchKeyEvent:], its window key), so the
// input method gets every modifier change twice. Whether a key down can come twice too (the owner's "#17", 0.6.7): the
// hash-digits script types "#17", and a key down through TSMProcessRawKeyEvent is recorded as well ("rawKeyDown").
// What the page does with a key the input method answers (0.6.7.2: Return on a suggestion row sent Slack's message;
// 0.6.7.3: ↓ ↑ → Esc on the rows moved Slack's caret, or the focus): the type-enter and type-keys scripts, the probe
// standing in for the input method (HARNESS_ANSWER, `standIn`).
//
// Environment: HARNESS_SCRIPT (shift-hold, shift-tap, shift-letter, option-tap, hash-digits, type-enter, type-keys),
// HARNESS_TYPE (what type-enter and type-keys type), HARNESS_KEYS (the keys type-keys presses after it, by name:
// return, tab, down, up, right, left, escape; type-enter's is return), HARNESS_ANSWER (the answer to each of them:
// `standIn`), HARNESS_AFTER (the page's text after the caret before anything is typed), HARNESS_DELAY (seconds before it starts,
// the page loaded), HARNESS_FAKE_KEY (the window says it's key, as it is while someone types in it: on a locked screen, or with
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

/// "<type> <keyCode> <flags> <timestamp, seconds into the script>[ <characters, percent-encoded>]"; `name` in place of
/// the type if given.
static NSString *recorded(NSEvent *e, NSString *name) {
    NSString *line = [NSString stringWithFormat:@"%@ %u 0x%lx %.4f", name ?: typeName(e), e.keyCode, (unsigned long)e.modifierFlags,
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
    if (e.type == NSEventTypeFlagsChanged) record(recorded(e, nil));
    // A key down this way too would be another way to the input method than the text input context's.
    if (e.type == NSEventTypeKeyDown) record(recorded(e, @"rawKeyDown"));
    return TSMProcessRawKeyEvent(event);
}
__attribute__((used, section("__DATA,__interpose"))) static struct {
    const void *replacement, *original;
} interposeTSM = {(const void *)probeTSMProcessRawKeyEvent, (const void *)TSMProcessRawKeyEvent};

static IMP originalHandleEvent, originalActivate, originalDeactivate;

// MARK: Standing in for the input method

/// HARNESS_ANSWER's steps (the type-enter script): the probe is the input method, and the system's gets none of the
/// keys. nil: the system's input method has them.
static NSArray<NSString *> *answer;
/// The field the probe answered last (whether it still has marked text, once the script is done).
static __weak id<NSTextInputClient> answered;

/// One of the answer's steps, `client` the field: "<key|after>:<insert|mark>:<location|none>:<length>:<selection>:<text,
/// percent-encoded>": insertText:replacementRange:, or setMarkedText: with the caret `selection` into it, by the range
/// given (none: NSNotFound). Recorded as "answer <key|after> <insert|mark> <location|none> <length> <selection> <text's
/// length>".
static void answerStep(id<NSTextInputClient> client, NSArray<NSString *> *parts) {
    NSString *text = [parts[5] stringByRemovingPercentEncoding] ?: @"";
    NSRange range = [parts[2] isEqualToString:@"none"] ? NSMakeRange(NSNotFound, 0)
                                                       : NSMakeRange((NSUInteger)parts[2].integerValue, (NSUInteger)parts[3].integerValue);
    record([NSString stringWithFormat:@"answer %@ %@ %@ %@ %@ %lu", parts[0], parts[1], parts[2], parts[3], parts[4],
            (unsigned long)text.length]);
    if ([parts[1] isEqualToString:@"mark"]) {
        [client setMarkedText:text selectedRange:NSMakeRange((NSUInteger)parts[4].integerValue, 0) replacementRange:range];
    } else {
        [client insertText:text replacementRange:range];
    }
}

/// The keys the answer's steps answer (the rest are typed), by the names HARNESS_KEYS gives them.
static NSDictionary<NSString *, NSNumber *> *answeredKeys(void) {
    return @{@"return": @(kVK_Return), @"tab": @(kVK_Tab), @"down": @(kVK_DownArrow), @"up": @(kVK_UpArrow),
             @"right": @(kVK_RightArrow), @"left": @(kVK_LeftArrow), @"escape": @(kVK_Escape)};
}

/// A key down answered as the input method would: a character key's text put in during it (insertText: with no
/// range, as an input method that types it does); ⏎, Tab, an arrow or Esc with the answer's steps, each during its key
/// down ("key:…") or on the run loop's next turn after it ("after:…"), none for an empty answer (the key taken, nothing
/// done: what 0.6.7.2 did on ↓). Every key is the input method's.
static BOOL standIn(id<NSTextInputClient> client, NSEvent *e) {
    answered = client;
    if (![answeredKeys().allValues containsObject:@(e.keyCode)]) {
        [client insertText:e.characters replacementRange:NSMakeRange(NSNotFound, 0)];
        return YES;
    }
    for (NSString *step in answer) {
        NSArray<NSString *> *parts = [step componentsSeparatedByString:@":"];
        if (parts.count != 6) {
            say(@"an answer's step not understood: %@", step);
            continue;
        }
        if ([parts[0] isEqualToString:@"after"]) {
            dispatch_async(dispatch_get_main_queue(), ^{ answerStep(client, parts); });
        } else {
            answerStep(client, parts);
        }
    }
    return YES;
}

static BOOL probeHandleEvent(NSTextInputContext *self, SEL _cmd, NSEvent *e) {
    say(@"-[NSTextInputContext handleEvent:] %@ < %@", describe(e), caller(3));
    // A key down reaches the input method here. With the context not active (no app is, the screen locked) it goes
    // no further: recorded as the input method would get it.
    if (e.type == NSEventTypeKeyDown) record(recorded(e, nil));
    if (answer && e.type == NSEventTypeKeyDown) return standIn(self.client, e);
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
// Left Option: key code 58, NSEventModifierFlagOption with NX_DEVICELALTKEYMASK (0x20).
static const NSEventModifierFlags leftOption = NSEventModifierFlagOption | 0x20 | 0x100;
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
    // "#17" typed as the owner did (⇧3, then 1 and 7), a little quicker; then a second for what comes late (a busy page
    // takes HARNESS_BUSY ms over each key down, and sends one it let go by through again only after that).
    if ([name isEqualToString:@"hash-digits"]) {
        void (^key)(NSEventType, unsigned short, NSString *, NSEventModifierFlags) =
            ^(NSEventType type, unsigned short code, NSString *characters, NSEventModifierFlags flags) {
                post(keyEvent(type, flags, code, characters));
            };
        return @[@[@0, shiftDown], @[@0.05, ^{ key(NSEventTypeKeyDown, 20, @"#", leftShift); }],
                 @[@0.05, ^{ key(NSEventTypeKeyUp, 20, @"#", leftShift); }], @[@0.03, shiftUp],
                 @[@0.07, ^{ key(NSEventTypeKeyDown, 18, @"1", noModifier); }],
                 @[@0.05, ^{ key(NSEventTypeKeyUp, 18, @"1", noModifier); }],
                 @[@0.3, ^{ key(NSEventTypeKeyDown, 26, @"7", noModifier); }],
                 @[@0.05, ^{ key(NSEventTypeKeyUp, 26, @"7", noModifier); }], @[@1.0, ^{}]];
    }
    // HARNESS_TYPE ("#17" without it) typed, the probe standing in for the input method (HARNESS_ANSWER), then ⏎ (or
    // type-keys' HARNESS_KEYS, one after another) answered with its steps; then a second for what comes after, and
    // whether the field still has marked text.
    if ([name isEqualToString:@"type-enter"] || [name isEqualToString:@"type-keys"]) {
        NSDictionary<NSString *, NSString *> *environment = NSProcessInfo.processInfo.environment;
        NSString *typed = environment[@"HARNESS_TYPE"] ?: @"#17";
        NSString *keys = [name isEqualToString:@"type-keys"] ? environment[@"HARNESS_KEYS"] ?: @"return" : @"return";
        NSDictionary<NSString *, NSNumber *> *codes = @{@"#": @20, @"0": @29, @"1": @18, @"2": @19, @"3": @20, @"4": @21,
                                                        @"5": @23, @"6": @22, @"7": @26, @"8": @28, @"9": @25};
        NSMutableArray *script = [NSMutableArray array];
        for (NSUInteger i = 0; i < typed.length; i++) {
            NSString *character = [typed substringWithRange:NSMakeRange(i, 1)];
            unsigned short code = codes[character].unsignedShortValue;
            NSEventModifierFlags flags = [character isEqualToString:@"#"] ? leftShift : noModifier;
            [script addObject:@[@0.1, ^{ post(keyEvent(NSEventTypeKeyDown, flags, code, character)); }]];
            [script addObject:@[@0.05, ^{ post(keyEvent(NSEventTypeKeyUp, flags, code, character)); }]];
        }
        // Each key's characters as AppKit has them: ⏎, Tab, Esc; an arrow's function key.
        NSDictionary<NSNumber *, NSString *> *characters = @{
            @(kVK_Return): @"\r", @(kVK_Tab): @"\t", @(kVK_Escape): @"\x1b",
            @(kVK_DownArrow): [NSString stringWithFormat:@"%C", (unichar)NSDownArrowFunctionKey],
            @(kVK_UpArrow): [NSString stringWithFormat:@"%C", (unichar)NSUpArrowFunctionKey],
            @(kVK_RightArrow): [NSString stringWithFormat:@"%C", (unichar)NSRightArrowFunctionKey],
            @(kVK_LeftArrow): [NSString stringWithFormat:@"%C", (unichar)NSLeftArrowFunctionKey]};
        double wait = 0.3;
        for (NSString *key in [keys componentsSeparatedByString:@","]) {
            NSNumber *code = answeredKeys()[key];
            if (!code) {
                say(@"a key not known: %@", key);
                continue;
            }
            // An arrow's events say so, as the system's do.
            NSEventModifierFlags flags = code.unsignedShortValue >= kVK_LeftArrow && code.unsignedShortValue <= kVK_UpArrow
                ? noModifier | NSEventModifierFlagFunction | NSEventModifierFlagNumericPad : noModifier;
            NSString *chars = characters[code];
            [script addObject:@[@(wait), ^{ post(keyEvent(NSEventTypeKeyDown, flags, code.unsignedShortValue, chars)); }]];
            [script addObject:@[@0.05, ^{ post(keyEvent(NSEventTypeKeyUp, flags, code.unsignedShortValue, chars)); }]];
            wait = 0.25;
        }
        [script addObject:@[@1.0, ^{
            id<NSTextInputClient> client = answered;
            record([NSString stringWithFormat:@"hasMarkedText %d", client ? (int)[client hasMarkedText] : -1]);
        }]];
        return script;
    }
    if ([name isEqualToString:@"option-tap"]) {
        return @[@[@0, ^{ post(keyEvent(NSEventTypeFlagsChanged, leftOption, 58, @"")); }],
                 @[@0.1, ^{ post(keyEvent(NSEventTypeFlagsChanged, noModifier, 58, @"")); }]];
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
    if (environment[@"HARNESS_ANSWER"]) {
        NSString *given = environment[@"HARNESS_ANSWER"];
        answer = given.length > 0 ? [given componentsSeparatedByString:@","] : @[];
    }
    NSArray *script = steps(name);
    if (!script) return;
    double delay = [environment[@"HARNESS_DELAY"] ?: @"3" doubleValue];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        scriptStart = up();
        record([NSString stringWithFormat:@"script %@ %@", name, NSBundle.mainBundle.bundleIdentifier]);
        run(script, 0);
    });
}
