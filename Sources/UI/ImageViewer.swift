import SwiftUI

// MARK: - 单张可缩放图片

/// 全屏查看用的图片。双击在 1x / 2.5x 之间切换，双指捏合连续缩放，
/// 放大后可以拖动，拖动范围限制在图片边界内。
struct ZoomableImage: View {
    let image: UIImage
    var onSaveToAlbum: (() -> Void)?
    var onCopy: (() -> Void)?

    @State private var scale: CGFloat = 1
    @State private var committedScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero

    private let maxScale: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: geo.size.width, height: geo.size.height)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(magnify(in: geo.size))
                .simultaneousGesture(drag(in: geo.size))
                .onTapGesture(count: 2) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                        if scale > 1.01 {
                            reset()
                        } else {
                            scale = 2.5
                            committedScale = 2.5
                        }
                    }
                }
                .contextMenu {
                    if let onSaveToAlbum {
                        Button(action: onSaveToAlbum) {
                            Label("保存到相册", systemImage: "square.and.arrow.down")
                        }
                    }
                    if let onCopy {
                        Button(action: onCopy) {
                            Label("复制图片", systemImage: "doc.on.doc")
                        }
                    }
                }
        }
    }

    private func magnify(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(committedScale * value.magnification, 1), maxScale)
            }
            .onEnded { _ in
                committedScale = scale
                if scale <= 1.01 {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        reset()
                    }
                } else {
                    let clamped = clamp(offset, in: size, scale: scale)
                    if clamped != offset {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            offset = clamped
                            committedOffset = clamped
                        }
                    } else {
                        committedOffset = offset
                    }
                }
            }
    }

    private func drag(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let next = CGSize(
                    width: committedOffset.width + value.translation.width,
                    height: committedOffset.height + value.translation.height
                )
                offset = clamp(next, in: size, scale: scale)
            }
            .onEnded { _ in
                committedOffset = offset
            }
    }

    private func clamp(_ value: CGSize, in size: CGSize, scale: CGFloat) -> CGSize {
        let maxX = max(0, (size.width * scale - size.width) / 2)
        let maxY = max(0, (size.height * scale - size.height) / 2)
        return CGSize(
            width: min(max(value.width, -maxX), maxX),
            height: min(max(value.height, -maxY), maxY)
        )
    }

    private func reset() {
        scale = 1
        committedScale = 1
        offset = .zero
        committedOffset = .zero
    }
}

// MARK: - 全屏画廊

/// 全屏看图：左右翻页、页码、底部缩略图条。缩略图条就是「只看图片」的那个视图。
struct ImageGalleryView: View {
    let images: [MessageImage]
    let initialIndex: Int

    @Environment(\.dismiss) private var dismiss
    @State private var index: Int?
    @State private var dragTranslation: CGFloat = 0
    @State private var toast: String?

    init(images: [MessageImage], initialIndex: Int) {
        self.images = images
        self.initialIndex = initialIndex
        _index = State(initialValue: min(max(initialIndex, 0), max(images.count - 1, 0)))
    }

    private var currentIndex: Int {
        index ?? initialIndex
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                Color.black
                    .opacity(backgroundOpacity)

                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(Array(images.enumerated()), id: \.offset) { offset, image in
                            Group {
                                if let ui = image.uiImage {
                                    ZoomableImage(
                                        image: ui,
                                        onSaveToAlbum: { saveToAlbum(ui) },
                                        onCopy: { copy(ui) }
                                    )
                                } else {
                                    Color.black
                                }
                            }
                            .frame(width: geo.size.width, height: geo.size.height)
                            .id(offset)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollPosition(id: $index)
                .scrollTargetBehavior(.paging)
                .scrollIndicators(.hidden)
                .frame(width: geo.size.width, height: geo.size.height)
                .offset(y: dragTranslation)
                .simultaneousGesture(dismissDrag)

                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 0)
                    if images.count > 1 {
                        thumbnailStrip
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .offset(y: dragTranslation)
                .opacity(1 - min(dragTranslation / 400, 0.6))

                if let toast {
                    Text(toast)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Color.white.opacity(0.2)))
                        .transition(.opacity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(Color.black)
        .ignoresSafeArea()
        .gesture(dismissDrag)
    }

    /// 下拉进度对应的背景不透明度。
    private var backgroundOpacity: Double {
        max(0.35, 1 - dragTranslation / 500)
    }

    /// 缩放为 1 时，向下拖到 140pt 就关掉；其他方向的拖动交给翻页和缩放。
    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                let height = value.translation.height
                guard height > 0, abs(value.translation.width) < abs(height) else { return }
                dragTranslation = height
            }
            .onEnded { value in
                let shouldClose = value.translation.height > 140
                    || value.predictedEndTranslation.height > 320
                if shouldClose {
                    dismiss()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                        dragTranslation = 0
                    }
                }
            }
    }

    private func saveToAlbum(_ image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        showToast("已保存到相册")
    }

    private func copy(_ image: UIImage) {
        UIPasteboard.general.image = image
        showToast("已复制图片")
    }

    private func showToast(_ text: String) {
        withAnimation(.easeOut(duration: 0.18)) {
            toast = text
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeIn(duration: 0.2)) {
                if toast == text {
                    toast = nil
                }
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.white.opacity(0.18)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭")

            Spacer()

            Text("\(currentIndex + 1) / \(images.count)")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.white.opacity(0.18)))
        }
        .padding(.horizontal, 18)
        .padding(.top, 46)
    }

    private var thumbnailStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(images.enumerated()), id: \.offset) { offset, image in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                index = offset
                            }
                        } label: {
                            Group {
                                if let ui = image.uiImage {
                                    Image(uiImage: ui)
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    Color.gray
                                }
                            }
                            .frame(width: 54, height: 54)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(
                                        offset == currentIndex ? Color.white : Color.white.opacity(0.18),
                                        lineWidth: offset == currentIndex ? 2 : 1
                                    )
                            )
                            .opacity(offset == currentIndex ? 1 : 0.65)
                        }
                        .buttonStyle(.plain)
                        .id(offset)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 6)
            }
            .background(.black.opacity(0.28))
            .onChange(of: currentIndex) { _, newValue in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
            .onAppear {
                proxy.scrollTo(currentIndex, anchor: .center)
            }
        }
        .frame(height: 74)
        .padding(.bottom, 6)
    }
}

// MARK: - 展示状态

/// `fullScreenCover(item:)` 需要 Identifiable。
struct GalleryPresentation: Identifiable {
    let id = UUID()
    let images: [MessageImage]
    let index: Int
}
