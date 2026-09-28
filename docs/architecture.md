# Architecture

Click has one application process. The SwiftPM targets retain the separation inherited from LoLiMouse:

| Target | Responsibility |
| --- | --- |
| `ClickApp` | SwiftUI settings, AppKit menu bar, permission guidance, optional login item |
| `ClickCore` | Local configuration, device registry, hardware reconciliation, input actions |
| `HIDPP` | Logitech feature discovery, protocol requests and responses |
| `HIDKit` | IOKit device monitoring, HID reports and pointer services |
| `IOKitSPI` | Narrow declarations for private input symbols |
| `ClickTests` | Dependency-free executable checks |

The UI stores desired configuration locally. Reconciliation applies enabled settings to supported devices. An event tap handles software scrolling and button actions; HID++ handles vendor-specific controls such as DPI, SmartShift and diverted buttons. This division lets ordinary mouse input continue through macOS while Click manages selected behavior.

The app has no external package dependencies, network service, account, or updater. `Scripts/check.sh privacy` rejects a bounded set of networking/client SDK patterns and package dependencies. It cannot prove the absence of every possible network path or replace code review.

Device detection, protocol feature discovery, a successful HID request, and verified physical behavior are different evidence. Changes to input processing need checks for release/cancellation and disconnect paths, plus testing on actual hardware before declaring a transport/model supported. Some behavior depends on private macOS APIs; compatibility must be reassessed after operating-system changes.

Application profiles replace button settings for the foreground bundle identifier; scrolling and pointer settings remain per-device. Unknown event senders pass through unchanged. For extra mouse buttons only, a hardware event with no sender ID uses the sole connected mouse only when the pointer-service inventory also has exactly one non-trackpad service; with multiple services or a process-generated event, Click does not guess. Consumed button releases remain paired with their presses across profile changes. Permission revocation disables routing and attempts hardware restoration. Restoration uses a shared deadline and recovers button diversion/raw movement before cosmetic settings; unavailable devices still require physical recovery. Explicit Refresh forces reconciliation even when a receiver retains its identity.

If macOS refuses to create an event tap despite reporting valid permissions, the existing permission timer retries every two seconds and the UI reports that button/scroll handling has not started. Success or disabling those customizations clears the error.
