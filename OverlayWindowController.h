#import <Cocoa/Cocoa.h>
#import "OverlayView.h"

@interface OverlayWindowController : NSWindowController
- (void)showWindow:(id)sender;
@property (nonatomic, strong) OverlayView *overlayView;
- (IBAction)handleCompactModeButton:(id)sender;
@end
