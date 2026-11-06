import SwiftUI
import UniformTypeIdentifiers

struct ScanPageFrames: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}

struct ScanWorkspaceView: View {
    @ObservedObject var scanner: ScanCoordinator
    @ObservedObject var store: ShelfStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(scanner.stage == .recognition ? (scanner.mode == .text ? String(localized: "Read text") : String(localized: "QR & barcodes")) : "Scan").font(Typography.heading)
                Spacer()
                if !scanner.isBusy {
                    Button(String(localized: "Sources")) { scanner.sources() }.font(Typography.button).foregroundStyle(Color.acid)
                    if !scanner.pages.isEmpty && scanner.stage != .pages {
                        Button(String(localized: "Pages (\(scanner.pages.count))")) { scanner.showPages() }.font(Typography.button)
                    }
                }
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    switch scanner.stage {
                    case .sources: sources
                    case .shelfPicker: shelfPicker
                    case .pages: pages
                    case .recognition: ScanRecognitionView(scanner: scanner)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if let error = scanner.error {
                NotchiState(title: error, error: true, actionTitle: String(localized: "Sources")) { scanner.sources() }
            }
            HStack(spacing: 7) {
                if scanner.isBusy { ProgressRing(progress: scanner.progress ?? 0.18, isComplete: false, isIndeterminate: scanner.progress == nil, size: 18) }
                if scanner.isBusy {
                    BlobMascot(gaze: .zero, isActive: true, isTargeted: false, isWorking: true, isReading: scanner.reading)
                        .scaleEffect(0.35).frame(width: 28, height: 25)
                    NotchiAttention(message: scanner.status)
                }
                if scanner.isBusy, let progress = scanner.progress {
                    Text(progress, format: .percent.precision(.fractionLength(0)))
                        .font(Typography.mono).monospacedDigit().foregroundStyle(Color.acid)
                }
                Spacer(minLength: 0)
                if scanner.isBusy { Button(String(localized: "Cancel")) { scanner.cancel() }.foregroundStyle(Color.coral).font(Typography.button) }
            }
        }
        .onPreferenceChange(ScanPageFrames.self) { scanner.pageFrames = $0 }
        .buttonStyle(NotchiButtonStyle(.secondary))
        .textFieldStyle(NotchiTextFieldStyle())
        .tint(Color.acid)
        .animation(reduceMotion ? Animations.fade : Animations.snappy, value: scanner.stage)
        .accessibilityElement(children: .contain).accessibilityLabel(String(localized: "Document scanner"))
    }
    private var sources: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(String(localized: "Add a page")).font(Typography.title).foregroundStyle(Color.acid)
            ContinuityCameraButton(scanner: scanner).frame(height: 34)
            PillButton(title: String(localized: "Shelf"), symbol: "square.stack", action: { scanner.pickShelf(store) })
            PillButton(title: String(localized: "Files"), symbol: "photo.on.rectangle", action: { scanner.chooseFiles() })
            PillButton(title: String(localized: "Capture"), symbol: "viewfinder", action: { scanner.captureArea() })
        }.padding(.vertical, 6)
    }
    private var shelfPicker: some View {
        VStack(alignment: .leading, spacing: 9) {
            let images = store.files.filter(\.isImage)
            if images.isEmpty {
                NotchiState(title: String(localized: "No images yet"), actionTitle: String(localized: "Files")) { scanner.chooseFiles() }
            }
            ForEach(images) { item in
                NotchiToggle(item.name, isOn: Binding(get: { scanner.selectedShelfIDs.contains(item.id) }, set: { value in
                    if value { scanner.selectedShelfIDs.insert(item.id) } else { scanner.selectedShelfIDs.remove(item.id) }
                })).font(Typography.body)
            }
            PillButton(title: String(localized: "Scan"), symbol: "doc.viewfinder", tint: .acid, prominent: true) {
                scanner.importInputs(images.filter { scanner.selectedShelfIDs.contains($0.id) }.map { .file($0.url) })
            }.disabled(scanner.selectedShelfIDs.isEmpty || scanner.isBusy)
        }
    }
    private var pages: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let page = scanner.selectedPage {
                ScanPagePreview(page: page, token: scanner.animationToken).frame(height: 132)
                if let warning = page.warning, !scanner.isBusy { NotchiAttention(message: String(localized: "Full image")).help(warning) }
            } else { Text(scanner.isBusy ? String(localized: "Finding edges…") : String(localized: "Add pages")).font(Typography.body).foregroundStyle(Color.secondaryText) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(Array(scanner.pages.enumerated()), id: \.element.id) { index, page in
                        VStack(spacing: 3) {
                            Button { scanner.selectedPageID = page.id } label: {
                                Image(decorative: page.preview, scale: 1).resizable().scaledToFit().frame(width: 42, height: 42)
                                    .padding(3).background(Color.shelfSurface, in: RoundedRectangle(cornerRadius: 7))
                                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(scanner.selectedPageID == page.id ? Color.acid : .shelfBorder))
                            }.accessibilityLabel(String(localized: "Scan page \(index + 1)"))
                            HStack(spacing: 4) {
                                Text(String(localized: "\(index + 1)")).font(Typography.caption)
                                Button { scanner.remove(page) } label: { Image(systemName: "xmark").font(Typography.caption) }
                                    .accessibilityLabel(String(localized: "Remove scan page \(index + 1)")).disabled(scanner.isBusy)
                            }
                        }
                        .background(GeometryReader { geometry in
                            Color.clear.preference(key: ScanPageFrames.self, value: [page.id: geometry.frame(in: .named("NotchiSend"))])
                        })
                        .onDrag {
                            guard !scanner.isBusy else { return NSItemProvider() }
                            scanner.draggingPageID = page.id; return NSItemProvider(object: page.id.uuidString as NSString)
                        }
                        .onDrop(of: [.utf8PlainText], delegate: ScanPageDrop(scanner: scanner, target: page.id))
                    }
                }.padding(.vertical, 3)
            }.frame(height: 90)
            NotchiSegmented(String(localized: "Look"), selection: Binding(get: { scanner.look }, set: { scanner.changeLook($0) }),
                options: ScanLook.allCases.map { NotchiOption($0, $0.rawValue) }).disabled(scanner.isBusy)
            NotchiToggle(String(localized: "Searchable"), isOn: $scanner.searchable).font(Typography.caption).disabled(scanner.isBusy)
            HStack {
                Button(String(localized: "Add pages")) { scanner.sources() }.font(Typography.button)
                Spacer()
                PillButton(title: String(localized: "Save PDF"), symbol: "doc.badge.plus", tint: .acid, prominent: true) { scanner.export(to: store) }
                    .disabled(scanner.pages.isEmpty || scanner.isBusy)
            }
        }
    }
}
private struct ScanPageDrop: DropDelegate {
    let scanner: ScanCoordinator
    let target: UUID
    func validateDrop(info: DropInfo) -> Bool { scanner.draggingPageID != nil && !scanner.isBusy }
    func dropEntered(info: DropInfo) {
        guard let source = scanner.draggingPageID else { return }
        withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? Animations.fade : Animations.snappy) { scanner.reorder(source: source, target: target) }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { scanner.draggingPageID = nil; return true }
}

private struct ScanRecognitionView: View {
    @ObservedObject var scanner: ScanCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = 0
    var body: some View {
        if let report = scanner.report, !report.pages.isEmpty {
            let index = min(max(0, scanner.reportPage), report.pages.count - 1)
            let page = report.pages[index]
            VStack(alignment: .leading, spacing: 9) {
                GeometryReader { geometry in
                    let rect = ScanCoordinates.fittedRect(imageSize: CGSize(width: page.image.width, height: page.image.height), canvas: geometry.size)
                    ZStack(alignment: .topLeading) {
                        Image(decorative: page.image, scale: 1).resizable().scaledToFit().frame(width: geometry.size.width, height: geometry.size.height)
                        ForEach(Array(page.lines.enumerated()), id: \.element.id) { i, line in
                            let box = ScanCoordinates.box(line.bounds, in: rect)
                            RoundedRectangle(cornerRadius: 2).fill(Color.acid.opacity(0.17))
                                .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.acid, lineWidth: 1))
                                .frame(width: box.width, height: box.height).position(x: box.midX, y: box.midY).opacity(i < visible ? 1 : 0)
                        }
                        ForEach(page.barcodes) { code in
                            let box = ScanCoordinates.box(code.bounds, in: rect)
                            RoundedRectangle(cornerRadius: 3).stroke(Color.mint, lineWidth: 2).frame(width: box.width, height: box.height).position(x: box.midX, y: box.midY)
                        }
                    }
                }.frame(height: 132).accessibilityLabel(String(localized: "Recognized text and barcode regions"))
                if report.pages.count > 1 {
                    NotchiPicker(String(localized: "Page"), selection: $scanner.reportPage,
                        options: report.pages.indices.map { NotchiOption($0, String(localized: "Page \($0 + 1)")) }).font(Typography.caption)
                }
                if scanner.mode == .text {
                    TextEditor(text: .constant(page.lines.prefix(visible).map(\.text).joined(separator: "\n")))
                        .font(Typography.body).frame(height: 95).scrollContentBackground(.hidden)
                        .padding(6).background(Color.shelfSurface, in: RoundedRectangle(cornerRadius: 8))
                    HStack {
                        Button(String(localized: "Copy text")) { scanner.copyText() }.font(Typography.button).foregroundStyle(Color.acid).disabled(report.text.isEmpty)
                        Text(String(localized: "\(page.lines.count) text regions")).font(Typography.caption).foregroundStyle(Color.secondaryText)
                    }
                    if let notice = report.languageNotice { NotchiAttention(message: String(localized: "Hindi unavailable"), isError: true).help(notice) }
                }
                ForEach(page.barcodes) { code in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(code.payload).font(Typography.body).textSelection(.enabled).lineLimit(3)
                        HStack {
                            if let url = code.webURL { Button(String(localized: "Open link ↗")) { NSWorkspace.shared.open(url) }.foregroundStyle(Color.acid) }
                            Button(String(localized: "Copy code")) { scanner.copyCode(code) }
                        }.font(Typography.button)
                    }.padding(9).frame(maxWidth: .infinity, alignment: .leading).background(Color.shelfSurface, in: RoundedRectangle(cornerRadius: 9))
                }
            }
            .task(id: "\(page.id)-\(reduceMotion)") {
                visible = reduceMotion ? page.lines.count : 0
                guard !reduceMotion else { return }
                do {
                    for value in 1...max(1, min(page.lines.count, 60)) {
                        try Task.checkCancellation()
                        withAnimation(Animations.snappy) { visible = value }
                        try await Task.sleep(for: .seconds(Motion.ocrBoxStagger))
                    }
                    withAnimation(Animations.snappy) { visible = page.lines.count }
                } catch { }
            }
        } else if scanner.isBusy {
            Text(scanner.mode == .text ? String(localized: "Reading the tiny print…") : String(localized: "Looking for codes…")).font(Typography.body).foregroundStyle(Color.secondaryText)
        }
    }
}
