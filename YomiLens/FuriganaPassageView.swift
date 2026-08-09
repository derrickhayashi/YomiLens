import CoreText
import SwiftUI
import UIKit

final class RubyTextView: UIView {
    var textInsets = UIEdgeInsets.zero {
        didSet {
            guard textInsets != oldValue else { return }
            invalidateTextLayout()
        }
    }
    var attributedText = NSAttributedString(string: "") {
        didSet {
            invalidateTextLayout()
        }
    }

    private var framesetter: CTFramesetter?
    private var lastDrawnSize = CGSize.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        guard bounds.size != lastDrawnSize else { return }
        lastDrawnSize = bounds.size
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(),
              let textFrame = textFrame(in: bounds) else {
            return
        }

        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        CTFrameDraw(textFrame, context)
        context.restoreGState()
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        guard let framesetter else {
            return .zero
        }

        let availableWidth = max(
            0,
            size.width - textInsets.left - textInsets.right
        )
        let suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: attributedText.length),
            nil,
            CGSize(width: availableWidth, height: .greatestFiniteMagnitude),
            nil
        )

        return CGSize(
            width: size.width,
            height: ceil(suggestedSize.height)
                + textInsets.top
                + textInsets.bottom
                + 2
        )
    }

    func characterIndex(at point: CGPoint) -> Int? {
        guard let textFrame = textFrame(in: bounds) else {
            return nil
        }

        let coreTextPoint = CGPoint(
            x: point.x,
            y: bounds.height - point.y
        )
        let lines = CTFrameGetLines(textFrame) as NSArray
        guard lines.count > 0 else {
            return nil
        }

        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(
            textFrame,
            CFRange(location: 0, length: 0),
            &origins
        )

        for index in 0..<lines.count {
            let line = lines[index] as! CTLine
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            let width = CGFloat(
                CTLineGetTypographicBounds(
                    line,
                    &ascent,
                    &descent,
                    &leading
                )
            )
            let origin = origins[index]
            let hitBounds = CGRect(
                x: origin.x - 3,
                y: origin.y - descent - 6,
                width: width + 6,
                height: ascent + descent + leading + 12
            )

            guard hitBounds.contains(coreTextPoint) else {
                continue
            }

            let stringIndex = CTLineGetStringIndexForPosition(
                line,
                CGPoint(
                    x: coreTextPoint.x - origin.x,
                    y: coreTextPoint.y - origin.y
                )
            )

            return stringIndex == kCFNotFound ? nil : stringIndex
        }

        return nil
    }

    @objc private func applicationDidBecomeActive() {
        // Core Text can retain stale ruby positions when this UIView survives
        // suspension. Rebuilding the framesetter keeps glyphs, ruby, and hit
        // testing on the same freshly measured frame after foregrounding.
        invalidateTextLayout()
    }

    private func invalidateTextLayout() {
        framesetter = CTFramesetterCreateWithAttributedString(
            attributedText as CFAttributedString
        )
        lastDrawnSize = .zero
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        setNeedsDisplay()
    }

    private func textFrame(in bounds: CGRect) -> CTFrame? {
        guard let framesetter,
              bounds.width > textInsets.left + textInsets.right,
              bounds.height > textInsets.top + textInsets.bottom else {
            return nil
        }

        let path = CGPath(
            rect: CGRect(
                x: textInsets.left,
                y: textInsets.bottom,
                width: bounds.width - textInsets.left - textInsets.right,
                height: bounds.height - textInsets.top - textInsets.bottom
            ),
            transform: nil
        )

        return CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: attributedText.length),
            path,
            nil
        )
    }
}

struct FuriganaPassageView: UIViewRepresentable {
    let text: String
    let spans: [FuriganaSpan]
    let tokens: [JapaneseToken]
    let onSelect: (JapaneseToken) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> RubyTextView {
        let textView = RubyTextView()
        textView.addGestureRecognizer(
            UITapGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.didTap(_:))
            )
        )
        return textView
    }

    func updateUIView(_ textView: RubyTextView, context: Context) {
        context.coordinator.parent = self
        let passageFont = UIFont.preferredFont(forTextStyle: .title2)
        textView.textInsets = UIEdgeInsets(
            top: passageFont.lineHeight * 0.6,
            left: 0,
            bottom: 2,
            right: 0
        )
        textView.attributedText = attributedPassage()
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: RubyTextView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width > 0 else {
            return nil
        }

        return uiView.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        )
    }

    private func attributedPassage() -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 12
        paragraphStyle.paragraphSpacing = 8
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.firstLineHeadIndent = 8
        paragraphStyle.headIndent = 8
        paragraphStyle.tailIndent = -8

        let attributedText = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .title2),
                .foregroundColor: UIColor.label,
                .paragraphStyle: paragraphStyle
            ]
        )

        let rubyAttribute = NSAttributedString.Key(
            kCTRubyAnnotationAttributeName as String
        )

        for span in spans where NSMaxRange(span.range) <= attributedText.length {
            let ruby = CTRubyAnnotationCreateWithAttributes(
                .auto,
                .none,
                .before,
                span.reading as CFString,
                [kCTRubyAnnotationSizeFactorAttributeName: 0.5] as CFDictionary
            )

            attributedText.addAttribute(
                rubyAttribute,
                value: ruby,
                range: span.range
            )
        }

        for token in interactiveTokens where NSMaxRange(token.textRange) <= attributedText.length {
            attributedText.addAttributes(
                [
                    .underlineStyle: NSUnderlineStyle([
                        .single,
                        .patternDot
                    ]).rawValue,
                    .underlineColor: UIColor.secondaryLabel
                ],
                range: token.textRange
            )
        }

        return attributedText
    }

    private var interactiveTokens: [JapaneseToken] {
        tokens.filter {
            $0.partOfSpeech != "particle" && $0.partOfSpeech != "symbol"
        }
    }

    final class Coordinator: NSObject {
        var parent: FuriganaPassageView

        init(parent: FuriganaPassageView) {
            self.parent = parent
        }

        @objc func didTap(_ gesture: UITapGestureRecognizer) {
            guard let textView = gesture.view as? RubyTextView,
                  let characterIndex = textView.characterIndex(
                    at: gesture.location(in: textView)
                  ),
                  let token = parent.interactiveTokens.first(where: {
                    NSLocationInRange(characterIndex, $0.textRange)
                  }) else {
                return
            }

            parent.onSelect(token)
        }
    }
}
