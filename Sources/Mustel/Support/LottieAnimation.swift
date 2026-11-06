import AppKit
import Foundation

/// A small Lottie renderer for the frame-by-frame vector animations bundled with Mustel.
///
/// The bundled files only contain static shape layers whose visibility changes from frame to
/// frame, so they can be rendered with Core Graphics without pulling in a full Lottie runtime.
struct LottieAnimation {
    let frameRate: Double
    let inFrame: Double
    let outFrame: Double
    let layers: [Layer]

    var frameCount: Int {
        max(0, Int(ceil(outFrame - inFrame)))
    }

    static func named(_ name: String, bundle: Bundle = .module) -> LottieAnimation? {
        let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Animations")
            ?? bundle.url(forResource: name, withExtension: "json")
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(LottieAnimation.self, from: data)
    }
}

extension LottieAnimation: Decodable {
    private enum CodingKeys: String, CodingKey {
        case frameRate = "fr"
        case inFrame = "ip"
        case outFrame = "op"
        case layers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        frameRate = try container.decodeIfPresent(Double.self, forKey: .frameRate) ?? 30
        inFrame = try container.decodeIfPresent(Double.self, forKey: .inFrame) ?? 0
        outFrame = try container.decodeIfPresent(Double.self, forKey: .outFrame) ?? 0
        layers = try container.decodeIfPresent([Layer].self, forKey: .layers) ?? []
    }
}

extension LottieAnimation {
    struct Layer: Decodable {
        let type: Int
        let inFrame: Double
        let outFrame: Double
        let transform: Transform
        let shapes: [ShapeItem]

        private enum CodingKeys: String, CodingKey {
            case type = "ty"
            case inFrame = "ip"
            case outFrame = "op"
            case transform = "ks"
            case shapes
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = try container.decodeIfPresent(Int.self, forKey: .type) ?? 0
            inFrame = try container.decodeIfPresent(Double.self, forKey: .inFrame) ?? 0
            outFrame = try container.decodeIfPresent(Double.self, forKey: .outFrame) ?? 0
            transform = try container.decodeIfPresent(Transform.self, forKey: .transform) ?? .identity
            shapes = try container.decodeIfPresent([ShapeItem].self, forKey: .shapes) ?? []
        }
    }

    struct Transform: Decodable {
        let anchor: CGPoint
        let position: CGPoint
        let scale: CGPoint
        let rotation: CGFloat
        let opacity: CGFloat

        static let identity = Transform(
            anchor: .zero,
            position: .zero,
            scale: CGPoint(x: 100, y: 100),
            rotation: 0,
            opacity: 100
        )

        private enum CodingKeys: String, CodingKey {
            case anchor = "a"
            case position = "p"
            case scale = "s"
            case rotation = "r"
            case opacity = "o"
        }

        init(anchor: CGPoint, position: CGPoint, scale: CGPoint, rotation: CGFloat, opacity: CGFloat) {
            self.anchor = anchor
            self.position = position
            self.scale = scale
            self.rotation = rotation
            self.opacity = opacity
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            anchor = container.decodePoint(forKey: .anchor) ?? .zero
            position = container.decodePoint(forKey: .position) ?? .zero
            scale = container.decodePoint(forKey: .scale) ?? CGPoint(x: 100, y: 100)
            rotation = container.decodeNumber(forKey: .rotation) ?? 0
            opacity = container.decodeNumber(forKey: .opacity) ?? 100
        }

        var matrix: CGAffineTransform {
            var transform = CGAffineTransform(translationX: position.x, y: position.y)
            transform = transform.rotated(by: rotation * .pi / 180)
            transform = transform.scaledBy(x: scale.x / 100, y: scale.y / 100)
            transform = transform.translatedBy(x: -anchor.x, y: -anchor.y)
            return transform
        }
    }

    struct ShapeItem: Decodable {
        enum Kind: String, Decodable {
            case group = "gr"
            case path = "sh"
            case fill = "fl"
            case merge = "mm"
            case transform = "tr"
            case unknown

            init(from decoder: Decoder) throws {
                let rawValue = try decoder.singleValueContainer().decode(String.self)
                self = Kind(rawValue: rawValue) ?? .unknown
            }
        }

        let kind: Kind
        let items: [ShapeItem]?
        let path: LottiePath?
        let color: [Double]?
        let transform: Transform?

        private enum CodingKeys: String, CodingKey {
            case type = "ty"
            case items = "it"
            case path = "ks"
            case color = "c"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            kind = try container.decodeIfPresent(Kind.self, forKey: .type) ?? .unknown
            items = try container.decodeIfPresent([ShapeItem].self, forKey: .items)
            transform = kind == .transform ? try? Transform(from: decoder) : nil

            if kind == .path,
               let property = try? container.decodeIfPresent(LottieProperty.self, forKey: .path),
               case let .path(path)? = property.value {
                self.path = path
            } else {
                path = nil
            }

            if kind == .fill,
               let property = try? container.decodeIfPresent(LottieProperty.self, forKey: .color),
               case let .vector(color)? = property.value {
                self.color = color
            } else {
                color = nil
            }
        }
    }
}

extension LottieAnimation {
    /// The bounding box of all visible vector paths in the composition.
    var contentBounds: CGRect {
        var bounds = CGRect.null
        for layer in layers where layer.type == 4 {
            guard layer.outFrame > inFrame, layer.inFrame < outFrame else { continue }
            for path in layer.paths(parentMatrix: layer.transform.matrix) {
                bounds = bounds.union(path.boundingBoxOfPath)
            }
        }
        return bounds.isNull ? CGRect(x: 0, y: 0, width: 500, height: 500) : bounds
    }

    func renderFrames(cropRect: CGRect, size: CGSize, scale: CGFloat = 3) -> [NSImage] {
        guard frameCount > 0, size.width > 0, size.height > 0 else { return [] }
        return (0..<frameCount).map { index in
            render(frame: inFrame + Double(index), cropRect: cropRect, size: size, scale: scale)
        }
    }

    private func render(frame: Double, cropRect: CGRect, size: CGSize, scale: CGFloat) -> NSImage {
        let pixelWidth = max(1, Int(ceil(size.width * scale)))
        let pixelHeight = max(1, Int(ceil(size.height * scale)))
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return NSImage(size: size)
        }
        representation.size = size

        guard let graphicsContext = NSGraphicsContext(bitmapImageRep: representation) else {
            return NSImage(size: size)
        }

        let previousContext = NSGraphicsContext.current
        NSGraphicsContext.current = graphicsContext
        let context = graphicsContext.cgContext
        context.clear(CGRect(x: 0, y: 0, width: size.width, height: size.height))
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        context.concatenate(fitTransform(for: cropRect, in: size))

        for layer in layers where layer.type == 4 && layer.inFrame <= frame && frame < layer.outFrame {
            draw(layer: layer, context: context)
        }

        NSGraphicsContext.current = previousContext

        let image = NSImage(size: size)
        image.addRepresentation(representation)
        image.isTemplate = true
        return image
    }

    private func fitTransform(for cropRect: CGRect, in size: CGSize) -> CGAffineTransform {
        guard cropRect.width > 0, cropRect.height > 0 else { return .identity }
        let scale = min(size.width / cropRect.width, size.height / cropRect.height)
        let offsetX = (size.width - cropRect.width * scale) / 2 - cropRect.minX * scale
        let offsetY = (size.height - cropRect.height * scale) / 2 - cropRect.minY * scale
        return CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: offsetX, ty: offsetY)
    }

    private func draw(layer: Layer, context: CGContext) {
        draw(
            items: layer.shapes,
            parentMatrix: layer.transform.matrix,
            opacity: layer.transform.opacity / 100,
            context: context
        )
    }

    private func draw(
        items: [ShapeItem],
        parentMatrix: CGAffineTransform,
        opacity: CGFloat,
        context: CGContext
    ) {
        let groupTransform = items.first(where: { $0.kind == .transform })?.transform ?? .identity
        let matrix = groupTransform.matrix.concatenating(parentMatrix)
        let groupOpacity = opacity * (groupTransform.opacity / 100)
        var paths: [CGPath] = []
        var fillColor: [Double]?

        for item in items {
            switch item.kind {
            case .path:
                if let path = item.path {
                    paths.append(transformed(path.cgPath, by: matrix))
                }
            case .fill:
                fillColor = item.color
            case .group:
                draw(
                    items: item.items ?? [],
                    parentMatrix: matrix,
                    opacity: groupOpacity,
                    context: context
                )
            default:
                break
            }
        }

        guard let fillColor, fillColor.count >= 3, !paths.isEmpty else { return }
        let alpha = groupOpacity * CGFloat(fillColor.count > 3 ? fillColor[3] : 1)
        context.setAlpha(alpha)
        context.setFillColor(CGColor(
            red: CGFloat(fillColor[0]),
            green: CGFloat(fillColor[1]),
            blue: CGFloat(fillColor[2]),
            alpha: 1
        ))
        for path in paths {
            context.addPath(path)
        }
        context.fillPath()
        context.setAlpha(1)
    }

    private func transformed(_ path: CGPath, by matrix: CGAffineTransform) -> CGPath {
        var matrix = matrix
        return path.copy(using: &matrix) ?? path
    }
}

private extension LottieAnimation.Layer {
    func paths(parentMatrix: CGAffineTransform) -> [CGPath] {
        collectPaths(in: shapes, parentMatrix: parentMatrix)
    }

    func collectPaths(in items: [LottieAnimation.ShapeItem], parentMatrix: CGAffineTransform) -> [CGPath] {
        let groupTransform = items.first(where: { $0.kind == .transform })?.transform ?? .identity
        let matrix = groupTransform.matrix.concatenating(parentMatrix)
        var paths: [CGPath] = []

        for item in items {
            switch item.kind {
            case .path:
                if let path = item.path {
                    var matrix = matrix
                    paths.append(path.cgPath.copy(using: &matrix) ?? path.cgPath)
                }
            case .group:
                paths.append(contentsOf: collectPaths(in: item.items ?? [], parentMatrix: matrix))
            default:
                break
            }
        }

        return paths
    }
}

enum LottieValue: Decodable {
    case number(Double)
    case vector([Double])
    case path(LottiePath)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            self = .number(number)
            return
        }
        if let vector = try? container.decode([Double].self) {
            self = .vector(vector)
            return
        }
        if let path = try? container.decode(LottiePath.self) {
            self = .path(path)
            return
        }
        throw DecodingError.typeMismatch(
            LottieValue.self,
            DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported Lottie value")
        )
    }
}

struct LottieProperty: Decodable {
    let value: LottieValue?

    private enum CodingKeys: String, CodingKey {
        case animated = "a"
        case keyframes = "k"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let isAnimated = (try? container.decode(Int.self, forKey: .animated)) == 1
        if isAnimated {
            let keyframes = try? container.decode([LottieKeyframe].self, forKey: .keyframes)
            value = keyframes?.first?.startValue
        } else {
            value = try? container.decode(LottieValue.self, forKey: .keyframes)
        }
    }
}

struct LottieKeyframe: Decodable {
    let startValue: LottieValue?

    private enum CodingKeys: String, CodingKey {
        case start = "s"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startValue = try? container.decode(LottieValue.self, forKey: .start)
    }
}

struct LottiePath: Decodable {
    let vertices: [CGPoint]
    let inTangents: [CGPoint]
    let outTangents: [CGPoint]
    let closed: Bool

    private enum CodingKeys: String, CodingKey {
        case vertices = "v"
        case inTangents = "i"
        case outTangents = "o"
        case closed = "c"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let vertices = try container.decodeIfPresent([[Double]].self, forKey: .vertices) ?? []
        let inTangents = try container.decodeIfPresent([[Double]].self, forKey: .inTangents) ?? []
        let outTangents = try container.decodeIfPresent([[Double]].self, forKey: .outTangents) ?? []
        closed = try container.decodeIfPresent(Bool.self, forKey: .closed) ?? false
        self.vertices = vertices.compactMap(Self.point)
        self.inTangents = inTangents.compactMap(Self.point)
        self.outTangents = outTangents.compactMap(Self.point)
    }

    private static func point(_ value: [Double]) -> CGPoint? {
        guard value.count >= 2 else { return nil }
        return CGPoint(x: value[0], y: value[1])
    }

    var cgPath: CGPath {
        let path = CGMutablePath()
        guard vertices.count > 1 else { return path }

        path.move(to: vertices[0])
        let segmentCount = closed ? vertices.count : vertices.count - 1
        for index in 0..<segmentCount {
            let nextIndex = (index + 1) % vertices.count
            let start = vertices[index]
            let end = vertices[nextIndex]
            let outTangent = outTangents.indices.contains(index) ? outTangents[index] : .zero
            let inTangent = inTangents.indices.contains(nextIndex) ? inTangents[nextIndex] : .zero
            path.addCurve(
                to: end,
                control1: CGPoint(x: start.x + outTangent.x, y: start.y + outTangent.y),
                control2: CGPoint(x: end.x + inTangent.x, y: end.y + inTangent.y)
            )
        }
        if closed {
            path.closeSubpath()
        }
        return path
    }
}

private extension KeyedDecodingContainer {
    func decodeNumber(forKey key: Key) -> CGFloat? {
        guard let property = try? decodeIfPresent(LottieProperty.self, forKey: key) else { return nil }
        switch property.value {
        case let .number(number):
            return number
        case let .vector(vector) where !vector.isEmpty:
            return vector[0]
        default:
            return nil
        }
    }

    func decodePoint(forKey key: Key) -> CGPoint? {
        guard let property = try? decodeIfPresent(LottieProperty.self, forKey: key) else { return nil }
        switch property.value {
        case let .number(number):
            return CGPoint(x: number, y: number)
        case let .vector(vector) where vector.count >= 2:
            return CGPoint(x: vector[0], y: vector[1])
        default:
            return nil
        }
    }
}
