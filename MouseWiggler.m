#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <CoreGraphics/CoreGraphics.h>

typedef NS_ENUM(NSInteger, MouseWigglerMode) {
    MouseWigglerModeKeepAwake = 0,
    MouseWigglerModeClickAndMove = 1,
};

@interface MouseWigglerApp : NSObject <NSApplicationDelegate>
@property NSStatusItem *statusItem;
@property NSTimer *timer;
@property NSTask *caffeinate;
@property BOOL enabled;
@property NSTimeInterval interval;
@property MouseWigglerMode mode;
@property CGPoint clickPoint;
@property BOOL hasClickPoint;
@property NSMenuItem *keepAwakeModeItem;
@property NSMenuItem *clickModeItem;
@property NSMenuItem *capturePositionItem;
@property NSMenuItem *runNowItem;
@end

@implementation MouseWigglerApp

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.enabled = YES;
    self.interval = 60.0;
    self.mode = MouseWigglerModeKeepAwake;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    self.hasClickPoint = [defaults boolForKey:@"hasClickPoint"];
    if (self.hasClickPoint) {
        self.clickPoint = CGPointMake([defaults doubleForKey:@"clickPointX"], [defaults doubleForKey:@"clickPointY"]);
    }
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.title = @"🐭";
    self.statusItem.button.toolTip = @"鼠标自动小助手";
    [self buildMenu];
    [self startKeepingAwake];
    [self scheduleTimer];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [self stopKeepingAwake];
}

- (void)buildMenu {
    NSMenu *menu = [[NSMenu alloc] init];

    NSMenuItem *toggle = [[NSMenuItem alloc] initWithTitle:@"暂停" action:@selector(toggleEnabled:) keyEquivalent:@"p"];
    toggle.target = self;
    [menu addItem:toggle];

    NSMenu *modeMenu = [[NSMenu alloc] init];
    self.keepAwakeModeItem = [[NSMenuItem alloc] initWithTitle:@"防黑屏（空闲时轻移）" action:@selector(changeMode:) keyEquivalent:@""];
    self.keepAwakeModeItem.target = self;
    self.keepAwakeModeItem.tag = MouseWigglerModeKeepAwake;
    self.keepAwakeModeItem.state = NSControlStateValueOn;
    [modeMenu addItem:self.keepAwakeModeItem];

    self.clickModeItem = [[NSMenuItem alloc] initWithTitle:@"定点点击后随机移动" action:@selector(changeMode:) keyEquivalent:@""];
    self.clickModeItem.target = self;
    self.clickModeItem.tag = MouseWigglerModeClickAndMove;
    [modeMenu addItem:self.clickModeItem];

    NSMenuItem *modeRoot = [[NSMenuItem alloc] initWithTitle:@"工作模式" action:nil keyEquivalent:@""];
    modeRoot.submenu = modeMenu;
    [menu addItem:modeRoot];

    NSMenu *intervalMenu = [[NSMenu alloc] init];
    NSArray<NSArray *> *choices = @[@[@"30 秒", @30.0], @[@"1 分钟", @60.0], @[@"2 分钟", @120.0], @[@"5 分钟", @300.0]];
    for (NSArray *choice in choices) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:choice[0] action:@selector(changeInterval:) keyEquivalent:@""];
        item.target = self;
        item.representedObject = choice[1];
        item.state = [choice[1] doubleValue] == self.interval ? NSControlStateValueOn : NSControlStateValueOff;
        [intervalMenu addItem:item];
    }
    NSMenuItem *intervalRoot = [[NSMenuItem alloc] initWithTitle:@"活动间隔" action:nil keyEquivalent:@""];
    intervalRoot.submenu = intervalMenu;
    [menu addItem:intervalRoot];

    [menu addItem:NSMenuItem.separatorItem];
    self.capturePositionItem = [[NSMenuItem alloc] initWithTitle:@"3 秒后记录点击位置" action:@selector(captureClickPosition:) keyEquivalent:@"l"];
    self.capturePositionItem.target = self;
    [menu addItem:self.capturePositionItem];
    [self updateCapturePositionTitle];

    self.runNowItem = [[NSMenuItem alloc] initWithTitle:@"现在动一下" action:@selector(runNow:) keyEquivalent:@"w"];
    self.runNowItem.target = self;
    [menu addItem:self.runNowItem];

    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"退出鼠标小助手" action:@selector(quitApp:) keyEquivalent:@"q"];
    quit.target = self;
    [menu addItem:quit];
    self.statusItem.menu = menu;
}

- (void)scheduleTimer {
    [self.timer invalidate];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:self.interval target:self selector:@selector(handleTimer:) userInfo:nil repeats:YES];
}

- (void)handleTimer:(NSTimer *)timer {
    if (!self.enabled) return;
    if (self.mode == MouseWigglerModeClickAndMove) {
        [self performClickCycle];
    } else {
        [self wiggleIfIdle:timer];
    }
}

- (void)wiggleIfIdle:(NSTimer *)timer {
    CGEventType types[] = {kCGEventMouseMoved, kCGEventLeftMouseDown, kCGEventRightMouseDown, kCGEventKeyDown, kCGEventScrollWheel};
    CFTimeInterval idle = DBL_MAX;
    for (NSUInteger i = 0; i < sizeof(types) / sizeof(types[0]); i++) {
        idle = MIN(idle, CGEventSourceSecondsSinceLastEventType(kCGEventSourceStateCombinedSessionState, types[i]));
    }
    if (idle >= self.interval * 0.8) [self wiggleCursor];
}

- (void)wiggleCursor {
    CGEventRef currentEvent = CGEventCreate(NULL);
    if (!currentEvent) return;
    CGPoint cgOriginal = CGEventGetLocation(currentEvent);
    CFRelease(currentEvent);
    CGRect displayBounds = CGDisplayBounds(CGMainDisplayID());
    CGFloat direction = cgOriginal.x + 2 < CGRectGetMaxX(displayBounds) ? 1 : -1;
    CGPoint nudged = CGPointMake(cgOriginal.x + direction, cgOriginal.y);

    CGWarpMouseCursorPosition(nudged);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        CGWarpMouseCursorPosition(cgOriginal);
    });
}

- (BOOL)ensureAccessibilityPermission {
    NSDictionary *options = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES};
    BOOL trusted = AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
    if (!trusted) {
        self.statusItem.button.toolTip = @"请在系统设置 → 隐私与安全性 → 辅助功能中允许鼠标自动小助手";
    }
    return trusted;
}

- (void)performClickCycle {
    if (!self.hasClickPoint) {
        self.statusItem.button.title = @"⚠️";
        self.statusItem.button.toolTip = @"请先选择“3 秒后记录点击位置”";
        return;
    }
    if (![self ensureAccessibilityPermission]) return;

    CGPoint target = self.clickPoint;
    CGWarpMouseCursorPosition(target);
    CGEventRef down = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDown, target, kCGMouseButtonLeft);
    CGEventRef up = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseUp, target, kCGMouseButtonLeft);
    if (down && up) {
        CGEventPost(kCGHIDEventTap, down);
        CGEventPost(kCGHIDEventTap, up);
    }
    if (down) CFRelease(down);
    if (up) CFRelease(up);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        CGWarpMouseCursorPosition([self randomSafePointAwayFrom:target]);
    });
}

- (CGPoint)randomSafePointAwayFrom:(CGPoint)target {
    CGRect bounds = CGDisplayBounds(CGMainDisplayID());
    CGFloat margin = 30.0;
    CGFloat width = MAX(1.0, CGRectGetWidth(bounds) - margin * 2.0);
    CGFloat height = MAX(1.0, CGRectGetHeight(bounds) - margin * 2.0);
    CGPoint point = target;
    for (NSInteger attempt = 0; attempt < 10; attempt++) {
        CGFloat randomX = (CGFloat)arc4random() / (CGFloat)UINT32_MAX;
        CGFloat randomY = (CGFloat)arc4random() / (CGFloat)UINT32_MAX;
        point = CGPointMake(CGRectGetMinX(bounds) + margin + randomX * width,
                            CGRectGetMinY(bounds) + margin + randomY * height);
        if (hypot(point.x - target.x, point.y - target.y) >= 100.0) break;
    }
    return point;
}

- (void)updateCapturePositionTitle {
    if (self.hasClickPoint) {
        self.capturePositionItem.title = [NSString stringWithFormat:@"3 秒后重设点击位置（%.0f, %.0f）", self.clickPoint.x, self.clickPoint.y];
    } else {
        self.capturePositionItem.title = @"3 秒后记录点击位置";
    }
}

- (void)startKeepingAwake {
    if (self.caffeinate) return;
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/caffeinate"];
    task.arguments = @[@"-d", @"-i"];
    NSError *error = nil;
    if ([task launchAndReturnError:&error]) {
        self.caffeinate = task;
    } else {
        self.statusItem.button.toolTip = @"鼠标自动小助手（防休眠启动失败）";
    }
}

- (void)stopKeepingAwake {
    if (self.caffeinate.running) [self.caffeinate terminate];
    self.caffeinate = nil;
}

- (void)toggleEnabled:(NSMenuItem *)sender {
    self.enabled = !self.enabled;
    sender.title = self.enabled ? @"暂停" : @"恢复";
    self.statusItem.button.title = self.enabled ? (self.mode == MouseWigglerModeClickAndMove ? @"🎯" : @"🐭") : @"💤";
    self.enabled ? [self startKeepingAwake] : [self stopKeepingAwake];
}

- (void)changeMode:(NSMenuItem *)sender {
    self.mode = (MouseWigglerMode)sender.tag;
    self.keepAwakeModeItem.state = self.mode == MouseWigglerModeKeepAwake ? NSControlStateValueOn : NSControlStateValueOff;
    self.clickModeItem.state = self.mode == MouseWigglerModeClickAndMove ? NSControlStateValueOn : NSControlStateValueOff;
    self.runNowItem.title = self.mode == MouseWigglerModeClickAndMove ? @"现在执行一次点击" : @"现在动一下";
    self.statusItem.button.title = self.mode == MouseWigglerModeClickAndMove ? @"🎯" : @"🐭";
    self.statusItem.button.toolTip = self.mode == MouseWigglerModeClickAndMove ? @"定点点击模式" : @"防黑屏模式";
    [self scheduleTimer];
    if (self.mode == MouseWigglerModeClickAndMove) {
        [self ensureAccessibilityPermission];
        if (!self.hasClickPoint) [self captureClickPosition:nil];
    }
}

- (void)changeInterval:(NSMenuItem *)sender {
    self.interval = [sender.representedObject doubleValue];
    for (NSMenuItem *item in sender.menu.itemArray) item.state = item == sender ? NSControlStateValueOn : NSControlStateValueOff;
    [self scheduleTimer];
}

- (void)captureClickPosition:(id)sender {
    self.statusItem.button.title = @"3️⃣";
    self.statusItem.button.toolTip = @"请在 3 秒内把鼠标移到要点击的位置";
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.statusItem.button.title = @"2️⃣";
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.statusItem.button.title = @"1️⃣";
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        CGEventRef event = CGEventCreate(NULL);
        if (!event) return;
        self.clickPoint = CGEventGetLocation(event);
        CFRelease(event);
        self.hasClickPoint = YES;
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        [defaults setBool:YES forKey:@"hasClickPoint"];
        [defaults setDouble:self.clickPoint.x forKey:@"clickPointX"];
        [defaults setDouble:self.clickPoint.y forKey:@"clickPointY"];
        [self updateCapturePositionTitle];
        self.statusItem.button.title = self.mode == MouseWigglerModeClickAndMove ? @"🎯" : @"🐭";
        self.statusItem.button.toolTip = [NSString stringWithFormat:@"已记录点击位置（%.0f, %.0f）", self.clickPoint.x, self.clickPoint.y];
    });
}

- (void)runNow:(id)sender {
    self.mode == MouseWigglerModeClickAndMove ? [self performClickCycle] : [self wiggleCursor];
}
- (void)quitApp:(id)sender { [NSApp terminate:nil]; }

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        MouseWigglerApp *delegate = [[MouseWigglerApp alloc] init];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [app run];
    }
    return 0;
}
