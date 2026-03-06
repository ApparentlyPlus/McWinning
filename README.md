# McWinning

McWinning is a small utility that remaps Windows-style keyboard shortcuts to their macOS equivalents. It intercepts keyboard events using `CGEventTap` and translates them so common Windows shortcuts behave as expected on macOS.

## Build

You can compile the program using `make`:

```bash
make
```

Alternatively, compile manually with `clang`:

```bash
mkdir bin
clang -O2 -framework ApplicationServices -framework Cocoa src/McWinning.m -o bin/McWinning
```

## Install

Copy the binary to a system path and make it executable:

```bash
sudo cp bin/McWinning /usr/local/bin/McWinning
sudo chmod +x /usr/local/bin/McWinning
```

## LaunchAgent (optional)

Create the following file:

```
/Library/LaunchDaemons/com.McWinning.remap.plist
```

Content:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.McWinning.remap</string>

    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/McWinning</string>
    </array>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <true/>

    <key>StandardErrorPath</key>
    <string>/tmp/com.McWinning.remap.err</string>

    <key>StandardOutPath</key>
    <string>/tmp/com.McWinning.remap.out</string>
</dict>
</plist>
```

## Start the service

```bash
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.McWinning.remap.plist
```

## Permissions

Because the program intercepts keyboard events, macOS requires **Accessibility permissions**. Add the `McWinning` binary to:

```
System Settings → Privacy & Security → Accessibility
```
