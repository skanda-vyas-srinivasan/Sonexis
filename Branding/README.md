# Sonexis branding

`sonexis-original-favicon.png` is the original 1024 × 1024 website favicon, copied unchanged from `AudioShaperWebsite/public/favicon.png`. This is the source of the sweeping S requested for Sonexis. Keep this file so the original logo cannot be lost again.

`sonexis-mark.png` is the reusable transparent pink mark. The Black theme brand color is solid `#FF2D95`; do not add gradients, bevels, or glow to the mark itself. The menu-bar asset is a black transparency template so macOS can tint it for the menu bar; the panel uses the app theme color.

Run `swift Scripts/render-app-icon.swift` from the repository root to regenerate the transparent mark, menu/panel template sizes, AppIcon sizes, and DockMark. The script isolates the original pink silhouette from the neutral scanline background, preserving its antialiased outline; it does not redraw the letter or substitute a font. The Dock icon uses the existing flat dark rounded tile.
