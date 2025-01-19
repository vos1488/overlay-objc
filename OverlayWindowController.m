#import "OverlayWindowController.h"
#import "OverlayView.h"

@implementation OverlayWindowController

- (id)init {
    NSScreen *screen = [NSScreen mainScreen];
    NSRect frame = screen.frame;
    
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                  styleMask:NSWindowStyleMaskBorderless
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
    
    [window setBackgroundColor:[NSColor clearColor]];
    [window setOpaque:NO];
    [window setLevel:CGWindowLevelForKey(kCGAssistiveTechHighWindowLevel)];
    [window setIgnoresMouseEvents:YES];
    [window setAcceptsMouseMovedEvents:YES];
    [window setSharingType:NSWindowSharingNone];
    
    NSWindowCollectionBehavior behavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
                                        NSWindowCollectionBehaviorStationary |
                                        NSWindowCollectionBehaviorTransient |
                                        NSWindowCollectionBehaviorIgnoresCycle;
    
    [window setCollectionBehavior:behavior];
    
    OverlayView *view = [[OverlayView alloc] initWithFrame:frame];
    [window setContentView:view];
    
    self = [super initWithWindow:window];
    return self;
}

- (void)showWindow:(id)sender {
    [super showWindow:sender];
    NSWindow *window = [self window];
    [window setLevel:CGWindowLevelForKey(kCGAssistiveTechHighWindowLevel)];
    [window makeKeyAndOrderFront:nil];
    [window display];
}

- (void)windowDidLoad {
    [super windowDidLoad];
    [self registerKeyboardShortcuts];
}

- (void)registerKeyboardShortcuts {
    NSEventMask eventMask = NSEventMaskKeyDown;
    [NSEvent addLocalMonitorForEventsMatchingMask:eventMask handler:^NSEvent *(NSEvent *event) {
        if ([event modifierFlags] & NSEventModifierFlagCommand) {
            switch ([event keyCode]) {
                case 12: // Q key
                    [[NSApplication sharedApplication] terminate:self];
                    break;
                case 4:  // H key
                    [[self window] orderOut:nil];
                    break;
                case 46: // M key
                    [self moveToNextDisplay];
                    break;
                case 15: // R key
                    [self refreshAllData];
                    break;
            }
        } else if ([event keyCode] == 53) { // ESC key
            [[self window] orderOut:nil];
        }
        return event;
    }];
}

- (void)moveToNextDisplay {
    NSArray *screens = [NSScreen screens];
    if (screens.count <= 1) return;
    
    NSWindow *window = [self window];
    NSScreen *currentScreen = [window screen];
    NSInteger currentIndex = [screens indexOfObject:currentScreen];
    NSInteger nextIndex = (currentIndex + 1) % screens.count;
    NSScreen *nextScreen = screens[nextIndex];
    
    NSRect frame = nextScreen.frame;
    [window setFrame:frame display:YES animate:YES];
}

- (void)refreshAllData {
    OverlayView *view = (OverlayView *)[self.window contentView];
    [view updateTime];
    [view updateBatteryInfo];
    [view updateIPAddresses];
    [view updateNetworkStatus];
}

@end
