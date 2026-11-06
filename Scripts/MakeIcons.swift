import AppKit
import Foundation

// A deliberately small native SVG renderer for this source's rect/ellipse
// primitives. Unsupported SVG elements fail rather than silently disappear.
final class IconSVG: NSObject, XMLParserDelegate {
    var elements: [(String,[String:String])] = []
    var invalid = false
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String:String]) {
        if ["rect","ellipse"].contains(name) { elements.append((name,attributes)) }
        else if name != "svg" { invalid = true }
    }
    func draw(size: Int, in context: CGContext) {
        context.saveGState(); defer { context.restoreGState() }
        context.scaleBy(x: CGFloat(size)/1024, y: CGFloat(size)/1024)
        for (name,a) in elements {
            func n(_ key: String) -> CGFloat { CGFloat(Double(a[key] ?? "0") ?? 0) }
            let hex = UInt32((a["fill"] ?? "#000000").dropFirst(),radix:16)!
            context.setFillColor(CGColor(red:CGFloat((hex>>16)&255)/255,green:CGFloat((hex>>8)&255)/255,blue:CGFloat(hex&255)/255,alpha:1))
            if name == "rect" {
                context.addPath(CGPath(roundedRect:CGRect(x:n("x"),y:n("y"),width:n("width"),height:n("height")),cornerWidth:n("rx"),cornerHeight:n("rx"),transform:nil)); context.fillPath()
            } else {
                let small = size <= 32 && a["data-eye"] == "true"
                let rx = n("rx") * (small ? 1.22 : 1), ry = n("ry") * (small ? 1.08 : 1)
                context.fillEllipse(in:CGRect(x:n("cx")-rx,y:n("cy")-ry,width:rx*2,height:ry*2))
            }
        }
    }
}
let root = URL(fileURLWithPath:CommandLine.arguments[1])
let svg = IconSVG(), parser = XMLParser(contentsOf:root.appendingPathComponent("Design/notchi-icon.svg"))!
parser.delegate=svg
precondition(parser.parse() && !svg.invalid,"Unsupported icon SVG")
let set=root.appendingPathComponent("Resources/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at:set,withIntermediateDirectories:true)
func png(_ size: Int, draw:(CGContext)->Void) -> Data {
    let ctx=CGContext(data:nil,width:size,height:size,bitsPerComponent:8,bytesPerRow:size*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    // The source SVG is top-down; keep the notch at the top of the output.
    ctx.translateBy(x:0,y:CGFloat(size));ctx.scaleBy(x:1,y:-1)
    ctx.setShouldAntialias(true);draw(ctx)
    return NSBitmapImageRep(cgImage:ctx.makeImage()!).representation(using:.png,properties:[:])!
}
var entries:[[String:String]]=[]
for pointSize in [16,32,128,256,512] {
    for scale in [1,2] {
        let pixels=pointSize*scale,name="icon_\(pointSize)x\(pointSize)@\(scale)x.png"
        try png(pixels) { svg.draw(size:pixels,in:$0) }.write(to:set.appendingPathComponent(name))
        entries.append(["idiom":"mac","size":"\(pointSize)x\(pointSize)","scale":"\(scale)x","filename":name])
    }
}
try JSONSerialization.data(withJSONObject:["images":entries,"info":["author":"xcode","version":1]],options:[.prettyPrinted,.sortedKeys]).write(to:set.appendingPathComponent("Contents.json"))
try Data("{\"info\":{\"author\":\"xcode\",\"version\":1}}".utf8).write(to:set.deletingLastPathComponent().appendingPathComponent("Contents.json"))
// One-color template: notch tab + eyes cut through its alpha, no colored tile.
for scale in [1,2] {
    let side=18*scale
    try png(side) { ctx in
        ctx.scaleBy(x:CGFloat(scale),y:CGFloat(scale))
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.addPath(CGPath(roundedRect:CGRect(x:1,y:2,width:16,height:14),cornerWidth:4,cornerHeight:4,transform:nil));ctx.fillPath()
        ctx.setBlendMode(.clear)
        ctx.fill(CGRect(x:6,y:0,width:6,height:5))
        ctx.fillEllipse(in:CGRect(x:4.5,y:8,width:2.5,height:3.5))
        ctx.fillEllipse(in:CGRect(x:11,y:8,width:2.5,height:3.5))
    }.write(to:root.appendingPathComponent("Resources/MenuBarTemplate\(scale == 2 ? "@2x" : "").png"))
}
print("Generated 10 app icons and 2 menu templates from the native vector source.")
