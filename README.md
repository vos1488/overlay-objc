# Overlay

A minimal, unobtrusive system overlay for macOS that displays time, battery status, and IP addresses.

## Features

- Transparent overlay window that stays on top of all windows
- Real-time system information:
  - Current time
  - Battery status and level with visual indicator
  - Local IP address
  - Public IP address
- Minimal UI with close button
- Ignores mouse events except for the close button area
- Supports all displays and spaces
- Built with native macOS frameworks

## System Requirements

- macOS 10.10 or later
- 64-bit processor (Intel or Apple Silicon)
- 50MB free disk space
- Basic network connectivity for public IP detection
- Administrator privileges for installation
- No additional dependencies required

## Installation

### From Release
1. Download the latest release from the releases page
2. Extract the ZIP archive
3. Move `Overlay.app` to your Applications folder

### Building from Source
1. Clone the repository:
```bash
git clone https://github.com/vos9/overlay-objc.git
cd overlay-objc
```

2. Build using make:
```bash
make release
```

3. The application will be built in `build/release/Overlay.app`

## Technical Details

### Architecture
- Written in Objective-C using Cocoa framework
- Uses IOKit for battery monitoring
- Network interfaces monitoring for IP detection
- Event-driven updates with efficient timers
- Minimal CPU and memory footprint

### Performance
- Lightweight window management
- Efficient drawing using NSBezierPath
- Optimized battery status monitoring
- Async network operations for IP detection
- Memory-efficient string handling

### Memory Management
- Efficient autorelease pool usage
- Minimal heap allocations
- Automatic memory cleanup
- No memory leaks
- Optimized string handling

### Network Usage
- Local IP detection: read-only network interface access
- Public IP detection: single HTTP request every 5 minutes
- Fallback mechanism for offline operation
- No background network activity
- Minimal bandwidth usage (<1KB per request)

### Power Management
- Low CPU impact (<0.1% in idle state)
- Efficient battery monitoring
- Sleep/wake handling
- Power event notifications
- Automatic updates pausing during battery saving mode

### Security
- No data collection or storage
- Local-only operation
- No network access except for public IP detection
- No background processes
- Sandboxed application

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘Q | Quit application |
| ⌘H | Hide overlay |
| ⌘M | Move to next display |
| ⌘R | Refresh all data |
| esc | Exit fullscreen |

## Usage

1. Launch the application
2. The overlay will appear on top of all windows
3. The overlay ignores mouse clicks except for the close button
4. To quit, click the close button (×) in the top-right corner

## Development

### Build Configurations

- Release build: `make release`
- Debug build: `make debug`
- Profile build: `make profile`

### Additional Commands

- Run static analyzer: `make analyze`
- Generate debug symbols: `make dsym`
- Create distribution package: `make dist`
- Clean build files: `make clean`
- Show all commands: `make help`

### Build Options

```bash
# Build Types
make release    # Optimized build with -O3
make debug      # Debug build with sanitizers
make profile    # Build with profiling support

# Development Tools
make analyze    # Run static code analyzer
make dsym       # Generate debug symbols
make sign       # Sign the application

# Distribution
make dist       # Create distribution package
make bundle     # Create application bundle
make install    # Install to Applications folder
```

### Project Structure

```
overlay-objc/
├── OverlayView.h/m       # Main view implementation
├── OverlayWindowController.h/m # Window management
├── main.m               # Application entry point
├── Makefile            # Build system
└── README.md           # Documentation
```

### Performance Metrics

| Metric | Value |
|--------|--------|
| CPU Usage (idle) | <0.1% |
| Memory Usage | ~10MB |
| Launch Time | <100ms |
| Battery Impact | Negligible |
| Network Usage | <1KB/5min |

### Known Limitations

- No support for macOS versions below 10.10
- Limited to system default font
- Single instance only
- No configuration UI (planned)
- Public IP detection requires internet connection

### Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Troubleshooting

### Common Issues

1. Window not appearing
   - Check if System Integrity Protection allows window overlays
   - Verify accessibility permissions

2. IP addresses not showing
   - Check network connection
   - Verify firewall settings
   - Wait for async update (up to 5 seconds)

3. Build issues
   - Ensure Xcode command line tools are installed
   - Check macOS version compatibility
   - Verify all dependencies are met

## License

Copyright © 2025 vos9.su. All rights reserved.

## Author

Created by vos9.su

## Version History

- ALPHA_1.0.1 - Initial release with basic functionality
- Future releases planned with additional features
