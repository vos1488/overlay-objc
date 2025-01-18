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

@end
