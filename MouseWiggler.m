#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>

@interface MouseWigglerApp : NSObject <NSApplicationDelegate>
@property NSStatusItem *statusItem;
@property NSTimer *timer;
@property NSTask *caffeinate;
@property BOOL enabled;
@property NSTimeInterval interval;
@end

@implementation MouseWigglerApp

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.enabled = YES;
    self.interval = 60.0;
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
    NSMenuItem *moveNow = [[NSMenuItem alloc] initWithTitle:@"现在动一下" action:@selector(wiggleNow:) keyEquivalent:@"w"];
    moveNow.target = self;
    [menu addItem:moveNow];

    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"退出鼠标小助手" action:@selector(quitApp:) keyEquivalent:@"q"];
    quit.target = self;
    [menu addItem:quit];
    self.statusItem.menu = menu;
}

- (void)scheduleTimer {
    [self.timer invalidate];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:self.interval target:self selector:@selector(wiggleIfIdle:) userInfo:nil repeats:YES];
}

- (void)wiggleIfIdle:(NSTimer *)timer {
    if (!self.enabled) return;

    CGEventType types[] = {kCGEventMouseMoved, kCGEventLeftMouseDown, kCGEventRightMouseDown, kCGEventKeyDown, kCGEventScrollWheel};
    CFTimeInterval idle = DBL_MAX;
    for (NSUInteger i = 0; i < sizeof(types) / sizeof(types[0]); i++) {
        idle = MIN(idle, CGEventSourceSecondsSinceLastEventType(kCGEventSourceStateCombinedSessionState, types[i]));
    }
    if (idle >= self.interval * 0.8) [self wiggleCursor];
}

- (void)wiggleCursor {
    NSPoint original = NSEvent.mouseLocation;
    NSScreen *currentScreen = nil;
    for (NSScreen *screen in NSScreen.screens) {
        if (NSPointInRect(original, screen.frame)) { currentScreen = screen; break; }
    }
    if (!currentScreen) currentScreen = NSScreen.mainScreen;
    if (!currentScreen) return;

    CGFloat desktopTop = 0;
    for (NSScreen *screen in NSScreen.screens) desktopTop = MAX(desktopTop, NSMaxY(screen.frame));
    CGPoint cgOriginal = CGPointMake(original.x, desktopTop - original.y);
    CGFloat direction = original.x + 2 < NSMaxX(currentScreen.frame) ? 1 : -1;
    CGPoint nudged = CGPointMake(cgOriginal.x + direction, cgOriginal.y);

    CGWarpMouseCursorPosition(nudged);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        CGWarpMouseCursorPosition(cgOriginal);
    });
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
    self.statusItem.button.title = self.enabled ? @"🐭" : @"💤";
    self.enabled ? [self startKeepingAwake] : [self stopKeepingAwake];
}

- (void)changeInterval:(NSMenuItem *)sender {
    self.interval = [sender.representedObject doubleValue];
    for (NSMenuItem *item in sender.menu.itemArray) item.state = item == sender ? NSControlStateValueOn : NSControlStateValueOff;
    [self scheduleTimer];
}

- (void)wiggleNow:(id)sender { [self wiggleCursor]; }
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
