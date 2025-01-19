#import <Cocoa/Cocoa.h>
#import <CoreVideo/CoreVideo.h>

@interface OverlayView : NSView
@property (strong, nonatomic) NSTimer *timer;
@property (strong, nonatomic) NSString *currentTime;
@property (strong, nonatomic) NSString *batteryStatus;
@property (assign, nonatomic) double batteryLevel;
@property (strong, nonatomic) NSString *localIP;
@property (strong, nonatomic) NSString *publicIP;
@property (strong, nonatomic) NSButton *closeButton;

// New properties
@property (assign, nonatomic) BOOL is24HourFormat;
@property (assign, nonatomic) BOOL showSeconds;
@property (assign, nonatomic) CGFloat opacity;
@property (assign, nonatomic) NSInteger fontSize;
@property (strong, nonatomic) NSString *networkStatus;

// Cache properties
@property (strong, nonatomic) NSCache *imageCache;
@property (strong, nonatomic) NSDate *lastNetworkUpdate;
@property (strong, nonatomic) NSTimer *weakTimer;
@property (assign, nonatomic) NSTimeInterval networkTimeout;

// Performance properties
@property (assign, nonatomic) BOOL needsFullRedraw;
@property (assign, nonatomic) CGRect dirtyRect;

// Calendar properties
@property (strong, nonatomic) NSCalendar *calendar;
@property (strong, nonatomic) NSDictionary *holidays;
@property (assign, nonatomic) BOOL showCalendar;
@property (assign, nonatomic) NSInteger selectedMonth;
@property (assign, nonatomic) NSInteger selectedYear;

// Animation properties
@property (assign, nonatomic) CGFloat animationProgress;
@property (assign, nonatomic) CVDisplayLinkRef displayLink;
@property (assign, nonatomic) BOOL isAnimating;

// Additional calendar properties
@property (strong, nonatomic) NSColor *todayColor;
@property (strong, nonatomic) NSColor *selectedDayColor;
@property (assign, nonatomic) NSInteger selectedDay;

// New methods
- (void)toggleTimeFormat;
- (void)updateNetworkStatus;
- (void)increaseOpacity;
- (void)decreaseOpacity;
- (void)resetToDefaults;

// Add these method declarations
- (void)updateTime;
- (void)updateBatteryInfo;
- (void)updateIPAddresses;

// New methods
- (void)invalidateCache;
- (void)optimizeTimers;
- (void)suspendUpdates;
- (void)resumeUpdates;

// Calendar methods
- (void)toggleCalendar;
- (void)nextMonth;
- (void)previousMonth;
- (void)updateCalendar;
- (BOOL)isHoliday:(NSDate *)date;
- (NSInteger)daysInCurrentMonth;  // Add this line

// Calendar interaction
- (void)handleCalendarClick:(NSPoint)point;
- (void)selectDate:(NSDate *)date;
- (void)animateCalendarOpen;
- (void)animateCalendarClose;

// Animation method
- (void)handleAnimation;

// New button property
@property (strong, nonatomic) NSButton *toggleCalendarButton;

@end
