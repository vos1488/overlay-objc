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
@property (assign, nonatomic) BOOL is24HourFormat;
@property (assign, nonatomic) BOOL showSeconds;
@property (assign, nonatomic) CGFloat opacity;
@property (assign, nonatomic) NSInteger fontSize;
@property (strong, nonatomic) NSString *networkStatus;
@property (strong, nonatomic) NSCache *imageCache;
@property (strong, nonatomic) NSDate *lastNetworkUpdate;
@property (strong, nonatomic) NSTimer *weakTimer;
@property (assign, nonatomic) NSTimeInterval networkTimeout;
@property (assign, nonatomic) BOOL needsFullRedraw;
@property (assign, nonatomic) CGRect dirtyRect;
@property (strong, nonatomic) NSCalendar *calendar;
@property (strong, nonatomic) NSDictionary *holidays;
@property (assign, nonatomic) BOOL showCalendar;
@property (assign, nonatomic) NSInteger selectedMonth;
@property (assign, nonatomic) NSInteger selectedYear;
@property (assign, nonatomic) CGFloat animationProgress;
@property (assign, nonatomic) CVDisplayLinkRef displayLink;
@property (assign, nonatomic) BOOL isAnimating;
@property (strong, nonatomic) NSColor *todayColor;
@property (strong, nonatomic) NSColor *selectedDayColor;
@property (assign, nonatomic) NSInteger selectedDay;
@property (assign, nonatomic) double cpuUsage;
@property (assign, nonatomic) double powerConsumption;
@property (strong, nonatomic) NSString *powerUsageStatus;
@property (assign, nonatomic) float cpuTemperature;
@property (assign, nonatomic) BOOL isDarkTheme;

// New monitoring properties
@property (assign, nonatomic) double memoryUsage;
@property (assign, nonatomic) double memoryTotal;
@property (strong, nonatomic) NSString *networkThroughput;
@property (assign, nonatomic) double cpuTemp;
@property (strong, nonatomic) NSString *settingsPath;

// Network monitoring properties
@property (assign, nonatomic) uint64_t lastBytesIn;
@property (assign, nonatomic) uint64_t lastBytesOut;
@property (assign, nonatomic) NSTimeInterval lastNetworkCheck;
@property (strong, nonatomic) NSTimer *networkUpdateTimer;

@property (strong, nonatomic) NSTimer *memoryUpdateTimer;

@property (assign, nonatomic) BOOL isCompactMode;

@property (strong, nonatomic) NSButton *settingsButton;

- (void)toggleTimeFormat;
- (void)updateNetworkStatus;
- (void)increaseOpacity;
- (void)decreaseOpacity;
- (void)resetToDefaults;
- (void)updateTime;
- (void)updateBatteryInfo;
- (void)updateIPAddresses;
- (void)invalidateCache;
- (void)optimizeTimers;
- (void)suspendUpdates;
- (void)resumeUpdates;
- (void)toggleCalendar;
- (void)nextMonth;
- (void)previousMonth;
- (void)updateCalendar;
- (BOOL)isHoliday:(NSDate *)date;
- (NSInteger)daysInCurrentMonth;
- (void)handleCalendarClick:(NSPoint)point;
- (void)selectDate:(NSDate *)date;
- (void)animateCalendarOpen;
- (void)animateCalendarClose;
- (void)handleAnimation;
- (void)updatePowerConsumption;
- (void)startPowerMonitoring;
- (void)stopPowerMonitoring;
- (void)setupControlButtons;
- (void)handleTimeFormatButton:(id)sender;
- (void)handleRefreshButton:(id)sender;
- (void)handleSettingsButton:(id)sender;
- (void)handleThemeButton:(id)sender;

// New methods
- (void)updateMemoryUsage;
- (void)updateNetworkThroughput;
- (void)updateCPUTemperature;
- (void)saveSettings;
- (void)loadSettings;

- (void)toggleCompactMode;

- (void)showSettingsDialog;

@end
