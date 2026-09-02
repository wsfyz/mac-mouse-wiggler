#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <CoreGraphics/CoreGraphics.h>

typedef NS_ENUM(NSInteger, MouseWigglerMode) {
    MouseWigglerModeKeepAwake = 0,
    MouseWigglerModeClickAndMove = 1,
};

@interface MouseWigglerApp : NSObject <NSApplicationDelegate>
@property NSStatusItem *statusItem;
@property NSTimer *operationTimer;
@property NSTimer *countdownTimer;
@property NSTask *caffeinate;
@property BOOL enabled;
@property BOOL sessionExpired;
@property NSTimeInterval interval;
@property NSTimeInterval defaultSessionDuration;
@property NSDate *sessionEndDate;
@property MouseWigglerMode mode;
@property CGPoint clickPoint;
@property BOOL hasClickPoint;
@property NSMenuItem *keepAwakeModeItem;
@property NSMenuItem *clickModeItem;
@property NSMenuItem *capturePositionItem;
@property NSMenuItem *runNowItem;
@property NSMenuItem *toggleItem;
@property NSMenuItem *statusTextItem;
@property NSMenuItem *remainingTextItem;
@property NSArray<NSMenuItem *> *sessionDurationItems;
@property NSArray<NSMenuItem *> *defaultDurationItems;
@end

@implementation MouseWigglerApp

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.enabled = YES;
    self.interval = 60.0;
    self.mode = MouseWigglerModeKeepAwake;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    self.defaultSessionDuration = [defaults doubleForKey:@"defaultSessionDuration"];
    if (self.defaultSessionDuration <= 0) self.defaultSessionDuration = 3600.0;
    self.hasClickPoint = [defaults boolForKey:@"hasClickPoint"];
    if (self.hasClickPoint) {
        self.clickPoint = CGPointMake([defaults doubleForKey:@"clickPointX"], [defaults doubleForKey:@"clickPointY"]);
    }
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.title = @"🐭";
    self.statusItem.button.toolTip = @"鼠标自动小助手";
    [self buildMenu];
    NSNotificationCenter *workspaceCenter = NSWorkspace.sharedWorkspace.notificationCenter;
    [workspaceCenter addObserver:self selector:@selector(systemBecameInactive:) name:NSWorkspaceSessionDidResignActiveNotification object:nil];
    [workspaceCenter addObserver:self selector:@selector(systemBecameInactive:) name:NSWorkspaceScreensDidSleepNotification object:nil];
    [self startSessionWithDuration:self.defaultSessionDuration];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
    [self.operationTimer invalidate];
    [self.countdownTimer invalidate];
    [self stopKeepingAwake];
}

- (void)buildMenu {
    NSMenu *menu = [[NSMenu alloc] init];

    self.statusTextItem = [[NSMenuItem alloc] initWithTitle:@"状态：防黑屏模式" action:nil keyEquivalent:@""];
    self.statusTextItem.enabled = NO;
    [menu addItem:self.statusTextItem];
    self.remainingTextItem = [[NSMenuItem alloc] initWithTitle:@"剩余时间：01:00:00" action:nil keyEquivalent:@""];
    self.remainingTextItem.enabled = NO;
    [menu addItem:self.remainingTextItem];

    self.toggleItem = [[NSMenuItem alloc] initWithTitle:@"暂停" action:@selector(toggleEnabled:) keyEquivalent:@"p"];
    self.toggleItem.target = self;
    [menu addItem:self.toggleItem];
    NSMenuItem *restart = [[NSMenuItem alloc] initWithTitle:@"重新开始计时" action:@selector(restartSession:) keyEquivalent:@"r"];
    restart.target = self;
    [menu addItem:restart];
    [menu addItem:NSMenuItem.separatorItem];

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

    NSArray<NSArray *> *durationChoices = @[
        @[@"15 分钟", @900.0], @[@"30 分钟", @1800.0], @[@"1 小时", @3600.0],
        @[@"2 小时", @7200.0], @[@"4 小时", @14400.0]
    ];

    NSMenu *sessionDurationMenu = [[NSMenu alloc] init];
    NSMutableArray<NSMenuItem *> *sessionItems = [[NSMutableArray alloc] init];
    for (NSArray *choice in durationChoices) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:choice[0] action:@selector(changeSessionDuration:) keyEquivalent:@""];
        item.target = self;
        item.representedObject = choice[1];
        [sessionDurationMenu addItem:item];
        [sessionItems addObject:item];
    }
    self.sessionDurationItems = sessionItems;
    NSMenuItem *sessionDurationRoot = [[NSMenuItem alloc] initWithTitle:@"本次自动停止" action:nil keyEquivalent:@""];
    sessionDurationRoot.submenu = sessionDurationMenu;
    [menu addItem:sessionDurationRoot];

    NSMenu *defaultDurationMenu = [[NSMenu alloc] init];
    NSMutableArray<NSMenuItem *> *defaultItems = [[NSMutableArray alloc] init];
    for (NSArray *choice in durationChoices) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:choice[0] action:@selector(changeDefaultDuration:) keyEquivalent:@""];
        item.target = self;
        item.representedObject = choice[1];
        item.state = fabs([choice[1] doubleValue] - self.defaultSessionDuration) < 0.5 ? NSControlStateValueOn : NSControlStateValueOff;
        [defaultDurationMenu addItem:item];
        [defaultItems addObject:item];
    }
    self.defaultDurationItems = defaultItems;
    NSMenuItem *defaultDurationRoot = [[NSMenuItem alloc] initWithTitle:@"默认运行时长（新会话）" action:nil keyEquivalent:@""];
    defaultDurationRoot.submenu = defaultDurationMenu;
    [menu addItem:defaultDurationRoot];

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

- (void)scheduleOperationTimer {
    [self.operationTimer invalidate];
    self.operationTimer = [NSTimer scheduledTimerWithTimeInterval:self.interval target:self selector:@selector(handleTimer:) userInfo:nil repeats:YES];
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
    // 只检查，不主动弹出系统权限提示（避免每次调用都触发系统弹窗）
    NSDictionary *options = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @NO};
    BOOL trusted = AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
    if (!trusted) {
        self.statusItem.button.title = @"🔒";
        self.statusItem.button.toolTip = @"需要辅助功能权限，点击菜单查看指引";
        [self promptOpenAccessibilitySettings];
    }
    return trusted;
}

- (void)promptOpenAccessibilitySettings {
    // 用应用内 alert 引导用户，只在用户点击"打开设置"时才跳转，不会反复弹系统提示
    static BOOL isShowing = NO;
    if (isShowing) return;
    isShowing = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"需要辅助功能权限";
        alert.informativeText = @"“鼠标自动小助手”需要辅助功能权限才能执行点击操作。\n\n请在“系统设置 → 隐私与安全性 → 辅助功能”中允许本应用，然后重新打开一次本应用。";
        [alert addButtonWithTitle:@"打开系统设置"];
        [alert addButtonWithTitle:@"稍后"];
        [NSApp activateIgnoringOtherApps:YES];
        NSModalResponse response = [alert runModal];
        if (response == NSAlertFirstButtonReturn) {
            NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"];
            [[NSWorkspace sharedWorkspace] openURL:url];
        }
        isShowing = NO;
    });
}

- (void)performClickCycle {
    if (!self.hasClickPoint) {
        self.statusItem.button.title = @"⚠️";
        self.statusItem.button.toolTip = @"请先选择“3 秒后记录点击位置”";
        return;
    }
    // 静默检查权限，无权限时只更新状态提示，不弹窗（避免定时器反复触发弹窗）
    NSDictionary *options = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @NO};
    if (!AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options)) {
        self.statusItem.button.title = @"🔒";
        self.statusItem.button.toolTip = @"需要辅助功能权限，点击菜单栏图标查看指引";
        return;
    }

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

- (void)startSessionWithDuration:(NSTimeInterval)duration {
    self.enabled = YES;
    self.sessionExpired = NO;
    self.sessionEndDate = [NSDate dateWithTimeIntervalSinceNow:duration];
    [self startKeepingAwake];
    [self scheduleOperationTimer];
    [self.countdownTimer invalidate];
    self.countdownTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(updateCountdown:) userInfo:nil repeats:YES];
    for (NSMenuItem *item in self.sessionDurationItems) {
        item.state = fabs([item.representedObject doubleValue] - duration) < 0.5 ? NSControlStateValueOn : NSControlStateValueOff;
    }
    [self updateStatusDisplay];
}

- (void)expireSession {
    if (self.sessionExpired) return;
    self.enabled = NO;
    self.sessionExpired = YES;
    self.sessionEndDate = nil;
    [self.operationTimer invalidate];
    self.operationTimer = nil;
    [self.countdownTimer invalidate];
    self.countdownTimer = nil;
    [self stopKeepingAwake];
    [self updateStatusDisplay];
}

- (void)updateCountdown:(NSTimer *)timer {
    if (!self.sessionEndDate) return;
    if ([self.sessionEndDate timeIntervalSinceNow] <= 0) {
        [self expireSession];
    } else {
        [self updateStatusDisplay];
    }
}

- (NSString *)formattedRemainingTime {
    NSTimeInterval remaining = self.sessionEndDate ? MAX(0, [self.sessionEndDate timeIntervalSinceNow]) : 0;
    NSInteger seconds = (NSInteger)ceil(remaining);
    return [NSString stringWithFormat:@"%02ld:%02ld:%02ld", (long)(seconds / 3600), (long)((seconds / 60) % 60), (long)(seconds % 60)];
}

- (void)updateStatusDisplay {
    NSString *modeName = self.mode == MouseWigglerModeClickAndMove ? @"定点点击模式" : @"防黑屏模式";
    if (self.sessionExpired) {
        self.statusItem.button.title = @"⏹";
        self.statusItem.button.toolTip = @"已自动停止，电脑可以正常休眠";
        self.statusTextItem.title = [NSString stringWithFormat:@"状态：已自动停止（%@）", modeName];
        self.remainingTextItem.title = @"剩余时间：00:00:00";
        self.toggleItem.title = @"重新开始";
    } else if (!self.enabled) {
        self.statusItem.button.title = @"💤";
        self.statusItem.button.toolTip = @"已暂停，自动停止倒计时仍在继续";
        self.statusTextItem.title = [NSString stringWithFormat:@"状态：已暂停（%@）", modeName];
        self.remainingTextItem.title = [NSString stringWithFormat:@"剩余时间：%@", [self formattedRemainingTime]];
        self.toggleItem.title = @"继续";
    } else {
        NSString *icon = self.mode == MouseWigglerModeClickAndMove ? @"🎯" : @"🐭";
        NSString *remaining = [self formattedRemainingTime];
        self.statusItem.button.title = [NSString stringWithFormat:@"%@ %@", icon, remaining];
        self.statusItem.button.toolTip = [NSString stringWithFormat:@"%@，剩余 %@", modeName, remaining];
        self.statusTextItem.title = [NSString stringWithFormat:@"状态：%@运行中", modeName];
        self.remainingTextItem.title = [NSString stringWithFormat:@"剩余时间：%@", remaining];
        self.toggleItem.title = @"暂停";
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
    if (self.sessionExpired) {
        [self startSessionWithDuration:self.defaultSessionDuration];
        return;
    }
    self.enabled = !self.enabled;
    if (self.enabled) {
        [self startKeepingAwake];
        [self scheduleOperationTimer];
    } else {
        [self.operationTimer invalidate];
        self.operationTimer = nil;
        [self stopKeepingAwake];
    }
    [self updateStatusDisplay];
}

- (void)changeMode:(NSMenuItem *)sender {
    self.mode = (MouseWigglerMode)sender.tag;
    self.keepAwakeModeItem.state = self.mode == MouseWigglerModeKeepAwake ? NSControlStateValueOn : NSControlStateValueOff;
    self.clickModeItem.state = self.mode == MouseWigglerModeClickAndMove ? NSControlStateValueOn : NSControlStateValueOff;
    self.runNowItem.title = self.mode == MouseWigglerModeClickAndMove ? @"现在执行一次点击" : @"现在动一下";
    if (self.enabled) [self scheduleOperationTimer];
    [self updateStatusDisplay];
    if (self.mode == MouseWigglerModeClickAndMove) {
        [self ensureAccessibilityPermission];
        if (!self.hasClickPoint) [self captureClickPosition:nil];
    }
}

- (void)changeInterval:(NSMenuItem *)sender {
    self.interval = [sender.representedObject doubleValue];
    for (NSMenuItem *item in sender.menu.itemArray) item.state = item == sender ? NSControlStateValueOn : NSControlStateValueOff;
    if (self.enabled) [self scheduleOperationTimer];
}

- (void)changeSessionDuration:(NSMenuItem *)sender {
    [self startSessionWithDuration:[sender.representedObject doubleValue]];
}

- (void)changeDefaultDuration:(NSMenuItem *)sender {
    self.defaultSessionDuration = [sender.representedObject doubleValue];
    [NSUserDefaults.standardUserDefaults setDouble:self.defaultSessionDuration forKey:@"defaultSessionDuration"];
    for (NSMenuItem *item in self.defaultDurationItems) item.state = item == sender ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)restartSession:(id)sender {
    [self startSessionWithDuration:self.defaultSessionDuration];
}

- (void)systemBecameInactive:(NSNotification *)notification {
    [self expireSession];
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
        self.statusItem.button.toolTip = [NSString stringWithFormat:@"已记录点击位置（%.0f, %.0f）", self.clickPoint.x, self.clickPoint.y];
        [self updateStatusDisplay];
    });
}

- (void)runNow:(id)sender {
    self.mode == MouseWigglerModeClickAndMove ? [self performClickCycle] : [self wiggleCursor];
}
- (void)quitApp:(id)sender { [NSApp terminate:nil]; }

@end

int main(void) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        MouseWigglerApp *delegate = [[MouseWigglerApp alloc] init];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [app run];
    }
    return 0;
}
