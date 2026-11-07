#import <AppKit/AppKit.h>
#import <ServiceManagement/ServiceManagement.h>
#import "LogoPWM.h"
#include <signal.h>

typedef NS_ENUM(NSInteger, LogoEffect) {
    LogoEffectSteady,
    LogoEffectBreathing,
    LogoEffectHeartbeat,
    LogoEffectBeacon,
};

static NSString *const LevelKey = @"Level";
static NSString *const EffectKey = @"Effect";
static NSString *const CustomKey = @"Custom";

// Slider positions: 0 is off, 1 is the level macOS chose, 2 is the hardware maximum.
static const double AutoPosition = 1;
static const double MaxPosition = 2;

static const NSTimeInterval AnimationInterval = 1.0 / 30;
static const NSTimeInterval SteadyInterval = 0.25;
static const NSTimeInterval WaitingInterval = 1;

static double smoothPulse(double time, double start, double duration) {
    double progress = (time - start) / duration;
    if (progress < 0 || progress >= 1) return 0;
    double wave = sin(M_PI * progress);
    return wave * wave;
}

static double effectBrightness(LogoEffect effect, double elapsed) {
    switch (effect) {
        case LogoEffectBreathing:
            return 0.25 + 0.75 * (1.0 + cos(elapsed * 2.0 * M_PI / 4.0)) / 2.0;
        case LogoEffectHeartbeat: {
            double phase = fmod(elapsed, 3.0);
            return MIN(1, 0.25 + 0.75 * smoothPulse(phase, 0, 0.45) +
                0.50 * smoothPulse(phase, 0.5, 0.5));
        }
        case LogoEffectBeacon:
            return 0.2 + 0.8 * smoothPulse(fmod(elapsed, 5.0), 0, 1.6);
        case LogoEffectSteady:
            return 1;
    }
    return 1;
}

// The back of a closed lid with a glowing emblem in the middle.
static NSImage *menuBarIcon(void) {
    NSImage *image = [NSImage imageWithSize:NSMakeSize(18, 18) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        [NSColor.blackColor setStroke];
        [NSColor.blackColor setFill];
        NSBezierPath *lid = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(1.5, 3.5, 15, 11) xRadius:2.2 yRadius:2.2];
        lid.lineWidth = 1.3;
        [lid stroke];
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(7.4, 7.4, 3.2, 3.2)] fill];
        NSBezierPath *rays = [NSBezierPath bezierPath];
        rays.lineWidth = 1.1;
        rays.lineCapStyle = NSLineCapStyleRound;
        for (int ray = 0; ray < 8; ray++) {
            double angle = ray * M_PI / 4;
            [rays moveToPoint:NSMakePoint(9 + 2.9 * cos(angle), 9 + 2.9 * sin(angle))];
            [rays lineToPoint:NSMakePoint(9 + 4.0 * cos(angle), 9 + 4.0 * sin(angle))];
        }
        [rays stroke];
        return YES;
    }];
    image.template = YES;
    image.accessibilityDescription = @"Lid Glow";
    return image;
}

@interface LogoMenu : NSObject <NSApplicationDelegate, NSPopoverDelegate>
@end

@implementation LogoMenu {
    NSStatusItem *_item;
    NSPopover *_popover;
    NSSlider *_slider;
    NSPopUpButton *_effect;
    NSTextField *_status;
    NSTextField *_levelLabel;
    NSButton *_loginItem;
    io_service_t _led;

    BOOL _custom;        // The user wants Lid Glow to drive the logo.
    BOOL _paused;        // The Mac or its display is asleep.
    BOOL _haveBaseline;  // _baseline holds the level macOS last set.
    PWM _baseline;
    PWM _lastWritten;
    NSTimer *_timer;
    NSTimeInterval _timerInterval;
    NSTimeInterval _started;
}

#pragma mark - Setup

- (NSTextField *)smallLabel:(NSString *)text frame:(NSRect)frame alignment:(NSTextAlignment)alignment {
    NSTextField *label = [NSTextField labelWithString:text];
    label.frame = frame;
    label.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    label.textColor = NSColor.secondaryLabelColor;
    label.alignment = alignment;
    return label;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    _item = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    _item.button.image = menuBarIcon();
    _item.button.toolTip = @"Lid Glow";
    _item.button.target = self;
    _item.button.action = @selector(togglePopover:);

    _popover = [NSPopover new];
    _popover.behavior = NSPopoverBehaviorTransient;
    _popover.delegate = self;
    _popover.contentViewController = [NSViewController new];
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 310, 226)];
    _popover.contentViewController.view = view;

    NSTextField *title = [NSTextField labelWithString:@"Lid Glow"];
    title.frame = NSMakeRect(16, 190, 120, 22);
    title.font = [NSFont boldSystemFontOfSize:15];
    [view addSubview:title];

    _levelLabel = [NSTextField labelWithString:@""];
    _levelLabel.frame = NSMakeRect(136, 191, 158, 20);
    _levelLabel.alignment = NSTextAlignmentRight;
    _levelLabel.textColor = NSColor.secondaryLabelColor;
    [view addSubview:_levelLabel];

    _slider = [NSSlider sliderWithValue:AutoPosition minValue:0 maxValue:MaxPosition
                                 target:self action:@selector(sliderChanged:)];
    _slider.accessibilityLabel = @"Logo brightness";
    _slider.continuous = YES;
    _slider.numberOfTickMarks = 3;
    _slider.frame = NSMakeRect(16, 158, 278, 26);
    [view addSubview:_slider];
    [view addSubview:[self smallLabel:@"Off" frame:NSMakeRect(16, 140, 60, 16) alignment:NSTextAlignmentLeft]];
    [view addSubview:[self smallLabel:@"Auto" frame:NSMakeRect(125, 140, 60, 16) alignment:NSTextAlignmentCenter]];
    [view addSubview:[self smallLabel:@"Max" frame:NSMakeRect(234, 140, 60, 16) alignment:NSTextAlignmentRight]];

    NSTextField *effectLabel = [NSTextField labelWithString:@"Effect"];
    effectLabel.frame = NSMakeRect(16, 110, 62, 22);
    [view addSubview:effectLabel];

    _effect = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(80, 108, 214, 26) pullsDown:NO];
    _effect.accessibilityLabel = @"Logo effect";
    [_effect addItemsWithTitles:@[@"Steady", @"Breathing", @"Heartbeat", @"Beacon"]];
    _effect.target = self;
    _effect.action = @selector(effectChanged:);
    [view addSubview:_effect];

    _status = [NSTextField wrappingLabelWithString:@""];
    _status.maximumNumberOfLines = 2;
    _status.frame = NSMakeRect(16, 68, 278, 34);
    [view addSubview:_status];

    _loginItem = [NSButton checkboxWithTitle:@"Open at login" target:self action:@selector(toggleLoginItem:)];
    _loginItem.frame = NSMakeRect(16, 42, 278, 20);
    [view addSubview:_loginItem];

    NSButton *automatic = [NSButton buttonWithTitle:@"Automatic" target:self action:@selector(automatic:)];
    automatic.frame = NSMakeRect(16, 8, 100, 28);
    [view addSubview:automatic];
    NSButton *quit = [NSButton buttonWithTitle:@"Quit" target:NSApp action:@selector(terminate:)];
    quit.frame = NSMakeRect(225, 8, 69, 28);
    [view addSubview:quit];

    [self refreshLoginItem];

    _led = openLogoPWM();
    if (!_led) {
        _status.stringValue = @"This Mac has no illuminated logo controller.";
        _slider.enabled = NO;
        _effect.enabled = NO;
        automatic.enabled = NO;
        return;
    }

    NSNotificationCenter *workspace = NSWorkspace.sharedWorkspace.notificationCenter;
    [workspace addObserver:self selector:@selector(pause:) name:NSWorkspaceWillSleepNotification object:nil];
    [workspace addObserver:self selector:@selector(pause:) name:NSWorkspaceScreensDidSleepNotification object:nil];
    [workspace addObserver:self selector:@selector(resume:) name:NSWorkspaceDidWakeNotification object:nil];
    [workspace addObserver:self selector:@selector(resume:) name:NSWorkspaceScreensDidWakeNotification object:nil];

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults registerDefaults:@{LevelKey: @(AutoPosition), EffectKey: @(LogoEffectSteady), CustomKey: @NO}];
    _slider.doubleValue = [defaults doubleForKey:LevelKey];
    NSInteger effect = [defaults integerForKey:EffectKey];
    [_effect selectItemAtIndex:(effect >= 0 && effect < _effect.numberOfItems) ? effect : LogoEffectSteady];

    if ([NSProcessInfo.processInfo.arguments containsObject:@"--breathe"]) {
        [_effect selectItemAtIndex:LogoEffectBreathing];
        [self begin];
        dispatch_async(dispatch_get_main_queue(), ^{ [self togglePopover:nil]; });
    } else if ([defaults boolForKey:CustomKey]) {
        [self begin];
    } else {
        [self showAutomatic];
    }
}

- (void)togglePopover:(id)sender {
    if (_popover.shown) {
        [_popover performClose:sender];
    } else {
        [self refreshLoginItem];
        [_popover showRelativeToRect:_item.button.bounds ofView:_item.button preferredEdge:NSRectEdgeMinY];
    }
}

#pragma mark - Controls

- (void)saveSettings {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setDouble:_slider.doubleValue forKey:LevelKey];
    [defaults setInteger:_effect.indexOfSelectedItem forKey:EffectKey];
    [defaults setBool:_custom forKey:CustomKey];
}

- (void)sliderChanged:(id)sender {
    // Snap to the automatic level so it is easy to return to.
    if (fabs(_slider.doubleValue - AutoPosition) < 0.04) _slider.doubleValue = AutoPosition;
    [self begin];
}

- (void)effectChanged:(id)sender {
    _started = NSProcessInfo.processInfo.systemUptime;
    [self begin];
}

- (void)automatic:(id)sender {
    [self restoreBaseline];
    _custom = NO;
    [self stopTimer];
    _slider.doubleValue = AutoPosition;
    [_effect selectItemAtIndex:LogoEffectSteady];
    [self saveSettings];
    [self showAutomatic];
}

- (void)showAutomatic {
    _levelLabel.stringValue = @"Automatic";
    _status.stringValue = @"macOS is controlling the logo. Move the slider or pick an effect.";
}

- (void)toggleLoginItem:(id)sender {
    SMAppService *service = SMAppService.mainAppService;
    NSError *error = nil;
    BOOL ok = _loginItem.state == NSControlStateValueOn
        ? [service registerAndReturnError:&error]
        : [service unregisterAndReturnError:&error];
    if (!ok) _status.stringValue = error.localizedDescription ?: @"Could not change the login item.";
    if (service.status == SMAppServiceStatusRequiresApproval) {
        _status.stringValue = @"Allow Lid Glow in System Settings > General > Login Items.";
        [SMAppService openSystemSettingsLoginItems];
    }
    [self refreshLoginItem];
}

- (void)refreshLoginItem {
    _loginItem.state = SMAppService.mainAppService.status == SMAppServiceStatusEnabled
        ? NSControlStateValueOn : NSControlStateValueOff;
}

#pragma mark - LED control

- (void)begin {
    if (!_led) return;
    _custom = YES;
    [self saveSettings];
    if (_paused) return;
    [self update:nil];
}

- (NSTimeInterval)desiredInterval {
    if (!_haveBaseline) return WaitingInterval;
    return _effect.indexOfSelectedItem == LogoEffectSteady ? SteadyInterval : AnimationInterval;
}

- (void)scheduleTimer {
    NSTimeInterval interval = [self desiredInterval];
    if (_timer && _timerInterval == interval) return;
    [_timer invalidate];
    _timerInterval = interval;
    _timer = [NSTimer timerWithTimeInterval:interval target:self selector:@selector(update:) userInfo:nil repeats:YES];
    _timer.tolerance = interval * 0.1;
    [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
}

- (void)stopTimer {
    [_timer invalidate];
    _timer = nil;
}

// The high period for the slider position and effect, or 0 to turn the logo off.
- (uint64_t)targetHigh {
    double position = _slider.doubleValue;
    if (position <= 0) return 0;

    uint64_t period = _baseline.high + _baseline.low;
    double base = _baseline.high;
    double max = period - 1;  // The driver needs a nonzero low period.
    double level = position <= AutoPosition
        ? position * base
        : base + (position - AutoPosition) * (max - base);
    double elapsed = MAX(0, NSProcessInfo.processInfo.systemUptime - _started);
    level *= effectBrightness(_effect.indexOfSelectedItem, elapsed);
    return (uint64_t)MIN(max, MAX(1, llround(level)));
}

- (void)update:(id)sender {
    if (!_custom || _paused) return;

    PWM current = readPWM(_led);
    if (!_haveBaseline || !samePWM(current, _lastWritten)) {
        // First run, or macOS set a new level (room light or screen brightness changed).
        if (!usablePWM(current)) {
            _haveBaseline = NO;
            _status.stringValue = @"Waiting for macOS to light the logo.";
            _levelLabel.stringValue = @"Waiting";
            [self scheduleTimer];
            return;
        }
        _baseline = current;
        _lastWritten = current;
        _haveBaseline = YES;
    }

    uint64_t high = [self targetHigh];
    uint64_t period = _baseline.high + _baseline.low;
    kern_return_t result = KERN_SUCCESS;
    if (high == 0) {
        if (current.high != 0) {
            result = setLogoEnabled(_led, NO);
            current = readPWM(_led);
            if (result == KERN_SUCCESS && current.high == 0) _lastWritten = current;
            else result = result ?: kIOReturnError;
        }
    } else if (high != current.high) {
        PWM target = { high, period - high, _baseline.clock };
        result = setPWM(_led, target);
        PWM observed = readPWM(_led);
        if (result == KERN_SUCCESS && reachedPWM(target, observed)) _lastWritten = observed;
        else result = result ?: kIOReturnError;
    }

    if (result != KERN_SUCCESS) {
        [self automatic:nil];
        _status.stringValue = [NSString stringWithFormat:
            @"macOS refused the change (0x%08x). A macOS update may have blocked it.", result];
        return;
    }

    [self showLevel];
    [self scheduleTimer];
}

- (void)showLevel {
    uint64_t period = _baseline.high + _baseline.low;
    double percent = _lastWritten.high * 100.0 / period;
    double autoPercent = _baseline.high * 100.0 / period;
    double position = _slider.doubleValue;
    if (position <= 0) {
        _levelLabel.stringValue = @"Off";
    } else if (_effect.indexOfSelectedItem == LogoEffectSteady) {
        _levelLabel.stringValue = [NSString stringWithFormat:@"%.0f%%", percent];
    } else {
        _levelLabel.stringValue = _effect.titleOfSelectedItem;
    }
    if (position == AutoPosition) {
        _status.stringValue = [NSString stringWithFormat:
            @"Following macOS (%.0f%% right now).", autoPercent];
    } else {
        _status.stringValue = [NSString stringWithFormat:
            @"%@ macOS's level (%.0f%%). Adjusts as room light changes.",
            position < AutoPosition ? @"Dimmer than" : @"Brighter than", autoPercent];
    }
}

// Hands the logo back to macOS at the level it last chose.
- (void)restoreBaseline {
    if (!_custom || !_haveBaseline || samePWM(_lastWritten, _baseline)) return;
    if (!samePWM(readPWM(_led), _lastWritten)) return;  // macOS already took over.
    if (setPWM(_led, _baseline) == KERN_SUCCESS) _lastWritten = _baseline;
}

- (void)pause:(NSNotification *)notification {
    if (_paused) return;
    [self restoreBaseline];
    [self stopTimer];
    _paused = YES;
    _haveBaseline = NO;
}

- (void)resume:(NSNotification *)notification {
    if (!_paused) return;
    _paused = NO;
    // Give macOS a moment to restore its own level after waking.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!self->_paused) [self update:nil];
    });
}

- (void)popoverDidClose:(NSNotification *)notification {
    [self saveSettings];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [self saveSettings];
    [self restoreBaseline];
    [self stopTimer];
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
    if (_led) IOObjectRelease(_led);
}
@end

int main(void) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        LogoMenu *delegate = [LogoMenu new];
        app.delegate = delegate;
        signal(SIGINT, SIG_IGN);
        signal(SIGTERM, SIG_IGN);
        dispatch_source_t interrupt = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGINT, 0, dispatch_get_main_queue());
        dispatch_source_t terminate = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGTERM, 0, dispatch_get_main_queue());
        dispatch_source_set_event_handler(interrupt, ^{ [app terminate:nil]; });
        dispatch_source_set_event_handler(terminate, ^{ [app terminate:nil]; });
        dispatch_activate(interrupt);
        dispatch_activate(terminate);
        [app run];
        dispatch_source_cancel(interrupt);
        dispatch_source_cancel(terminate);
    }
    return 0;
}
