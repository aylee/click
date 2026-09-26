# Attribution and artwork

Click is a fork of [LoLiMouse](https://github.com/fedorananin/lolimouse), based on
revision [`750c3fb630cd8fca1d65cc77be59e8e44ae149b0`](https://github.com/fedorananin/lolimouse/tree/750c3fb630cd8fca1d65cc77be59e8e44ae149b0).
Its imported implementation includes HID access, the HID++ protocol,
configuration, event processing, reconciliation, app lifecycle and tests.
Click adds an MX Master-focused interface and adapts these components.

The upstream copyright and MIT terms are preserved in [LICENSE](LICENSE), with
an additional notice for Click contributions. The license and this notice are
included in packaged apps.

LoLiMouse credits [LinearMouse](https://github.com/linearmouse/linearmouse) (MIT)
and [OpenLogi](https://github.com/AprilNEA/OpenLogi) (MIT/Apache-2.0) as protocol
and implementation references. They are not dependencies of Click.

The Dock icon and in-app mouse illustration are original generated artwork
created for Click with OpenAI imagegen. Their PNGs and creation prompts are in
`Resources/` and `Sources/ClickApp/Resources/`. Project-provided artwork is
included under the repository's MIT terms to the extent applicable rights exist.
No Logitech marketing image or logo is bundled in this source tree.
`Scripts/build_icon.swift` generates the native icon sizes locally from the
committed PNG; no generation service is used to build or run the app.

The mouse illustration is a guide to control locations, not a manufacturer
product image. Click is independent and is not affiliated with or endorsed by
Logitech. Logitech, MX Master and Logi Options+ identify the hardware and
software being discussed.
