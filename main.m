#import <Cocoa/Cocoa.h>
#import "OverlayWindowController.h"

@interface AppDelegate : NSObject <NSApplicationDelegate>
@end

@implementation AppDelegate
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    return NSTerminateNow;
}
@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // Check command-line arguments for compact mode flag
        BOOL compactMode = NO;
        for (int i = 1; i < argc; i++) {
            if (strcmp(argv[i], "--compact") == 0) {
                compactMode = YES;
                break;
            }
        }
        
        NSApplication *application = [NSApplication sharedApplication];
        
        // Правильная загрузка иконки
        NSString *imagePath = [[NSBundle mainBundle] pathForResource:@"icon" ofType:@"png"];
        NSImage *icon = [[NSImage alloc] initWithContentsOfFile:imagePath];
        [application setApplicationIconImage:icon];
        
        [application setActivationPolicy:NSApplicationActivationPolicyAccessory];
        
        AppDelegate *delegate = [[AppDelegate alloc] init];
        [application setDelegate:delegate];
        
        OverlayWindowController *windowController = [[OverlayWindowController alloc] init];
        if (compactMode) {
            [windowController.overlayView toggleCompactMode];
        }
        [windowController showWindow:nil];
        
        [application run];
    }
    return 0;
}
