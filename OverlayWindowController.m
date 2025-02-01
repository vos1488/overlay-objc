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
    [window setMovable:NO];
    [window setMovableByWindowBackground:NO];
    [window setSharingType:NSWindowSharingNone];

    [window setAlphaValue:1.0];
    [window setOpaque:NO];
    [window setHasShadow:NO];
    
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
    // Set the overlayView property by casting the window contentView
    self.overlayView = (OverlayView *)self.window.contentView;
}

- (void)refreshAllData {
    OverlayView *view = (OverlayView *)[self.window contentView];
    [view updateTime];
    [view updateBatteryInfo];
    [view updateIPAddresses];
    [view updateNetworkStatus];
}

- (void)handleCompactModeButton:(id)sender {
    // Toggle compact mode on the overlay view and request a redraw
    [self.overlayView toggleCompactMode];
}

@end
