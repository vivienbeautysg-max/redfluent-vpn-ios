# AppIcon.png

This is a placeholder 1024x1024 icon (red `RF` on red background) generated
on the cloud Mac during the first TestFlight upload (2026-05-09).

The actual `AppIcon.png` binary is committed by the cloud Mac, not by the
Windows working copy.

To regenerate the placeholder on a Mac:

```sh
cat > /tmp/makeicon.swift <<'EOF'
import Cocoa
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
NSColor(red: 0.83, green: 0.18, blue: 0.18, alpha: 1.0).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
let attrs: [NSAttributedString.Key: Any] = [
  .font: NSFont.boldSystemFont(ofSize: 360),
  .foregroundColor: NSColor.white
]
let str = NSAttributedString(string: "RF", attributes: attrs)
let strSize = str.size()
let pt = NSPoint(x: (size.width - strSize.width)/2, y: (size.height - strSize.height)/2)
str.draw(at: pt)
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
let png = bitmap.representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
EOF
swift /tmp/makeicon.swift App/Assets.xcassets/AppIcon.appiconset/AppIcon.png
```

Replace this placeholder with a real designed icon before App Store submission.
