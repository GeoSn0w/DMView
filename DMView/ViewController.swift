//
//  ViewController.swift
//  DMView
//
//  Created by GeoSn0w on 7/11/26.
//

import Cocoa
import AVFoundation
import UniformTypeIdentifiers

class ViewController: NSViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    let previewLayer = AVCaptureVideoPreviewLayer()
    let videoOut = AVCaptureVideoDataOutput()
    let sampleQueue = DispatchQueue(label: "scope.frames")
    var popup: NSPopUpButton!
    var resPopup: NSPopUpButton!
    var previewBox: NSView!
    var zoomSlider: NSSlider!
    var zoomLabel: NSTextField!
    var statusLabel: NSTextField!
    var recButton: NSButton!
    var cameras: [AVCaptureDevice] = []
    var resFormats: [AVCaptureDevice.Format] = []
    var currentDevice: AVCaptureDevice?
    var zoom: CGFloat = 1.0
    let bufLock = NSLock()
    var latestBuffer: CVPixelBuffer?
    let ciCtx = CIContext()
    let recLock = NSLock()
    var recording = false
    var sessionStarted = false
    var assetWriter: AVAssetWriter?
    var writerInput: AVAssetWriterInput?
    var recStart: Date?
    var recTimer: Timer?

    func makeLabel(_ s: String) -> NSTextField {
        let t = NSTextField()
        t.stringValue = s
        t.isEditable = false
        t.isBezeled = false
        t.isSelectable = false
        t.drawsBackground = false
        t.translatesAutoresizingMaskIntoConstraints = false
        return t
    }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 940, height: 700))
        root.wantsLayer = true
        self.view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        let resTitle = makeLabel("Resolution:")
        let snap = NSButton(title: "Save Frame", target: self, action: #selector(saveFrame(_:)))
        let camTitle = makeLabel("Camera:")
        let plus = NSButton(title: "+", target: self, action: #selector(zoomIn))
        let minus = NSButton(title: "\u{2212}", target: self, action: #selector(zoomOut))
        
        popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.target = self
        popup.action = #selector(pickCamera(_:))
        popup.translatesAutoresizingMaskIntoConstraints = false
        resPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        resPopup.target = self
        resPopup.action = #selector(pickResolution(_:))
        resPopup.translatesAutoresizingMaskIntoConstraints = false
        recButton = NSButton(title: "Record", target: self, action: #selector(toggleRecord))
        recButton.bezelStyle = .rounded
        recButton.translatesAutoresizingMaskIntoConstraints = false
        previewBox = NSView()
        previewBox.wantsLayer = true
        previewBox.layer?.backgroundColor = NSColor(white: 0.12, alpha: 1).cgColor
        previewBox.layer?.cornerRadius = 8
        previewBox.layer?.borderWidth = 1
        previewBox.layer?.borderColor = NSColor(white: 0.3, alpha: 1).cgColor
        previewBox.layer?.masksToBounds = true
        previewBox.translatesAutoresizingMaskIntoConstraints = false
        previewLayer.videoGravity = .resizeAspect
        previewLayer.session = session
        previewBox.layer?.addSublayer(previewLayer)
        zoomSlider = NSSlider(value: 1, minValue: 1, maxValue: 8, target: self, action: #selector(zoomChanged(_:)))
        zoomSlider.translatesAutoresizingMaskIntoConstraints = false
        zoomLabel = makeLabel("1.0x")
        zoomLabel.alignment = .right
        statusLabel = makeLabel("")
        statusLabel.textColor = .secondaryLabelColor
        
        minus.bezelStyle = .rounded
        minus.translatesAutoresizingMaskIntoConstraints = false
        plus.bezelStyle = .rounded
        plus.translatesAutoresizingMaskIntoConstraints = false
        snap.bezelStyle = .rounded
        snap.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(camTitle)
        view.addSubview(popup)
        view.addSubview(resTitle)
        view.addSubview(resPopup)
        view.addSubview(snap)
        view.addSubview(recButton)
        view.addSubview(previewBox)
        view.addSubview(minus)
        view.addSubview(zoomSlider)
        view.addSubview(plus)
        view.addSubview(zoomLabel)
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            plus.leadingAnchor.constraint(equalTo: zoomSlider.trailingAnchor, constant: 8),
            plus.centerYAnchor.constraint(equalTo: minus.centerYAnchor),
            plus.widthAnchor.constraint(equalToConstant: 34),
            camTitle.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            camTitle.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            resTitle.leadingAnchor.constraint(equalTo: popup.trailingAnchor, constant: 16),
            resTitle.centerYAnchor.constraint(equalTo: camTitle.centerYAnchor),
            snap.trailingAnchor.constraint(equalTo: recButton.leadingAnchor, constant: -8),
            snap.centerYAnchor.constraint(equalTo: camTitle.centerYAnchor),
            minus.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            minus.topAnchor.constraint(equalTo: previewBox.bottomAnchor, constant: 12),
            minus.widthAnchor.constraint(equalToConstant: 34),
    
            popup.leadingAnchor.constraint(equalTo: camTitle.trailingAnchor, constant: 8),
            popup.centerYAnchor.constraint(equalTo: camTitle.centerYAnchor),
            popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 210),
            resPopup.leadingAnchor.constraint(equalTo: resTitle.trailingAnchor, constant: 8),
            resPopup.centerYAnchor.constraint(equalTo: camTitle.centerYAnchor),
            resPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 130),
            recButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            recButton.centerYAnchor.constraint(equalTo: camTitle.centerYAnchor),
            recButton.widthAnchor.constraint(equalToConstant: 84),
            previewBox.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            previewBox.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            previewBox.topAnchor.constraint(equalTo: popup.bottomAnchor, constant: 14),
            zoomSlider.leadingAnchor.constraint(equalTo: minus.trailingAnchor, constant: 8),
            zoomSlider.centerYAnchor.constraint(equalTo: minus.centerYAnchor),
            zoomLabel.leadingAnchor.constraint(equalTo: plus.trailingAnchor, constant: 10),
            zoomLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            zoomLabel.centerYAnchor.constraint(equalTo: minus.centerYAnchor),
            zoomLabel.widthAnchor.constraint(equalToConstant: 52),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            statusLabel.topAnchor.constraint(equalTo: minus.bottomAnchor, constant: 10),
            statusLabel.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -10)
        ])

        videoOut.alwaysDiscardsLateVideoFrames = true
        videoOut.videoSettings = [String(kCVPixelBufferPixelFormatTypeKey): kCVPixelFormatType_32BGRA]
        videoOut.setSampleBufferDelegate(self, queue: sampleQueue)

        let notifCtr = NotificationCenter.default
        notifCtr.addObserver(self, selector: #selector(devicesChanged), name: NSNotification.Name("AVCaptureDeviceWasConnectedNotification"), object: nil)
        notifCtr.addObserver(self, selector: #selector(devicesChanged), name: NSNotification.Name("AVCaptureDeviceWasDisconnectedNotification"), object: nil)

        if #available(macOS 10.14, *) {
            let status = AVCaptureDevice.authorizationStatus(for: .video)

            switch status {
            case .authorized:
                print("Camera status: AUTHORIZED")
                self.reloadCameras()

            case .notDetermined:
                print("Camera status: NOT DETERMINED - requesting permission...")

                AVCaptureDevice.requestAccess(for: .video) { granted in
                    DispatchQueue.main.async {
                        print("Permission dialog result:", granted)

                        if granted {
                            self.reloadCameras()
                        } else {
                            self.statusLabel.stringValue = "Camera permission denied."
                        }
                    }
                }

            case .denied:
                print("Camera status: DENIED")
                self.statusLabel.stringValue = "Camera access denied in System Settings."

            case .restricted:
                print("Camera status: RESTRICTED")
                self.statusLabel.stringValue = "Camera access is restricted."

            @unknown default:
                print("Camera status: UNKNOWN")
                self.statusLabel.stringValue = "Unknown camera permission state."
            }
        } else {
            reloadCameras()
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.transform = CATransform3DIdentity
        previewLayer.frame = previewBox.bounds
        previewLayer.transform = CATransform3DMakeScale(zoom, zoom, 1)
        CATransaction.commit()
        view.window?.title = "DMView - A Digital Microscope Viewer by GeoSn0w (@FCE365)" //heh
    }

    func discoverCameras() -> [AVCaptureDevice] {
        if #available(macOS 10.15, *) {
            let disc = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.external, .builtInWideAngleCamera],
                mediaType: .video,
                position: .unspecified
            )
            return disc.devices
        } else {
            return AVCaptureDevice.devices().filter { $0.hasMediaType(.video) }
        }
    }

    func reloadCameras() {
        cameras = discoverCameras().filter {
            let n = $0.localizedName.lowercased()
            return !n.contains("obs") && !n.contains("virtual")
        }

        popup.removeAllItems()
        for c in cameras {
            popup.addItem(withTitle: c.localizedName)
        }

        if cameras.isEmpty {
            statusLabel.stringValue = "No camera found. Plug in the microscope."
            session.stopRunning()
            currentDevice = nil
            resPopup.removeAllItems()
            return
        }

        var target = cameras.first {
            let n = $0.localizedName.lowercased()
            return n.contains("uvc") || n.contains("microscope") || n.contains("general")
        }
        if target == nil {
            target = cameras.first
        }

        if let t = target {
            popup.selectItem(withTitle: t.localizedName)
            useDevice(t)
        }
    }

    func useDevice(_ device: AVCaptureDevice) {
        currentDevice = device
        session.beginConfiguration()

        for i in session.inputs {
            session.removeInput(i)
        }
        if session.outputs.contains(videoOut) == false {
            if session.canAddOutput(videoOut) {
                session.addOutput(videoOut)
            }
        }

        guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            session.commitConfiguration()
            statusLabel.stringValue = "Couldn't open \(device.localizedName)."
            return
        }
        session.addInput(input)
        session.commitConfiguration()

        buildResolutions(device)
        statusLabel.stringValue = "Live: \(device.localizedName)"

        sampleQueue.async {
            if self.session.isRunning == false {
                self.session.startRunning()
            }
        }
    }

    func buildResolutions(_ device: AVCaptureDevice) {
        let sorted = device.formats.sorted { a, b in
            let da = CMVideoFormatDescriptionGetDimensions(a.formatDescription)
            let db = CMVideoFormatDescriptionGetDimensions(b.formatDescription)
            return Int(da.width) * Int(da.height) > Int(db.width) * Int(db.height)
        }

        resFormats = []
        var seen = Set<String>()
        resPopup.removeAllItems()
        for f in sorted {
            let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
            let key = "\(d.width)x\(d.height)"
            if seen.contains(key) { continue }
            seen.insert(key)
            resFormats.append(f)
            var fps = 0.0
            for r in f.videoSupportedFrameRateRanges where r.maxFrameRate > fps {
                fps = r.maxFrameRate
            }
            resPopup.addItem(withTitle: "\(d.width)\u{00D7}\(d.height) @\(Int(fps))")
        }

        if let first = resFormats.first {
            resPopup.selectItem(at: 0)
            applyFormat(first)
        }
    }

    func applyFormat(_ format: AVCaptureDevice.Format) {
        guard let dev = currentDevice else {
            return
        }
        
        if (try? dev.lockForConfiguration()) != nil {
            dev.activeFormat = format
            if let rate = format.videoSupportedFrameRateRanges.first {
                dev.activeVideoMinFrameDuration = rate.minFrameDuration
            }
            dev.unlockForConfiguration()
        }
        applyZoom()
    }

    @objc func pickCamera(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        if idx >= 0 && idx < cameras.count {
            useDevice(cameras[idx])
        }
    }

    @objc func pickResolution(_ sender: NSPopUpButton) {
        let indexOSI = sender.indexOfSelectedItem
        if indexOSI >= 0 && indexOSI < resFormats.count {
            applyFormat(resFormats[indexOSI])
        }
    }

    @objc func devicesChanged() {
        DispatchQueue.main.async {
            let had = self.currentDevice
            self.reloadCameras()
            
            if let h = had, self.cameras.contains(where: { $0.uniqueID == h.uniqueID }) {
                self.popup.selectItem(withTitle: h.localizedName)
            }
        }
    }

    func applyZoom() {
        if zoom < 1 {
            zoom = 1
        }
        
        if zoom > 8 {
            zoom = 8
        }
        
        zoomSlider.doubleValue = Double(zoom)
        zoomLabel.stringValue = String(format: "%.1fx", zoom)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.transform = CATransform3DIdentity
        previewLayer.frame = previewBox.bounds
        previewLayer.transform = CATransform3DMakeScale(zoom, zoom, 1)
        CATransaction.commit()
    }

    @objc func zoomChanged(_ sender: NSSlider) {
        zoom = CGFloat(sender.doubleValue)
        applyZoom()
    }

    @objc func zoomIn() {
        zoom += 0.5
        applyZoom()
    }

    @objc func zoomOut() {
        zoom -= 0.5
        applyZoom()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        bufLock.lock()
        latestBuffer = pb
        bufLock.unlock()

        recLock.lock()
        if recording, let w = assetWriter, let inp = writerInput {
            if !sessionStarted {
                w.startWriting()
                w.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                sessionStarted = true
            }
            if inp.isReadyForMoreMediaData {
                inp.append(sampleBuffer)
            }
        }
        recLock.unlock()
    }

    @objc func saveFrame(_ sender: Any?) {
        bufLock.lock()
        let pb = latestBuffer
        bufLock.unlock()

        guard let buffer = pb else {
            statusLabel.stringValue = "No frame yet."
            return
        }

        var ci = CIImage(cvPixelBuffer: buffer)
        if zoom > 1 {
            let ext = ci.extent
            let w = ext.width / zoom
            let h = ext.height / zoom
            let crop = CGRect(x: ext.midX - w / 2, y: ext.midY - h / 2, width: w, height: h)
            ci = ci.cropped(to: crop)
        }

        guard let cg = ciCtx.createCGImage(ci, from: ci.extent) else { return }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "microscopeCapture.png"
        if #available(macOS 11.0, *) {
            panel.allowedContentTypes = [.png]
        }
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            let rep = NSBitmapImageRep(cgImage: cg)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: url)
                DispatchQueue.main.async {
                    self.statusLabel.stringValue = "Saved \(url.lastPathComponent)"
                }
            }
        }
    }

    @objc func toggleRecord() {
        if recording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        guard let d = currentDevice else { return }
        let dims = CMVideoFormatDescriptionGetDimensions(d.activeFormat.formatDescription)

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "microscopeVid.mov"
        if #available(macOS 11.0, *) {
            panel.allowedContentTypes = [.quickTimeMovie]
        }
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            try? FileManager.default.removeItem(at: url)

            guard let writer = try? AVAssetWriter(url: url, fileType: .mov) else {
                self.statusLabel.stringValue = "Couldn't create movie file."
                return
            }

            let codec: Any
            
            if #available(macOS 10.13, *) {
                codec = AVVideoCodecType.h264
            } else {
                codec = AVVideoCodecH264
            }
            
            let settings: [String: Any] = [
                AVVideoCodecKey: codec,
                AVVideoWidthKey: Int(dims.width),
                AVVideoHeightKey: Int(dims.height)
            ]
            
            let inp = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            inp.expectsMediaDataInRealTime = true
            
            if writer.canAdd(inp) {
                writer.add(inp)
            }

            self.recLock.lock()
            self.assetWriter = writer
            self.writerInput = inp
            self.sessionStarted = false
            self.recording = true
            self.recLock.unlock()
            self.recStart = Date()
            self.recButton.title = "Stop"
            self.popup.isEnabled = false
            self.resPopup.isEnabled = false
            self.recTimer = Timer.scheduledTimer(timeInterval: 0.5, target: self, selector: #selector(self.tickRec), userInfo: nil, repeats: true)
            
            if #available(macOS 10.14, *) {
                self.recButton.contentTintColor = .systemRed
            }
        }
    }

    @objc func tickRec() {
        guard let s = recStart else {
            return
        }
        
        let t = Int(Date().timeIntervalSince(s))
        statusLabel.stringValue = String(format: "Recording  %02d:%02d", t / 60, t % 60)
    }

    func stopRecording() {
        recLock.lock()
        recording = false
        let w = assetWriter
        let inp = writerInput
        assetWriter = nil
        writerInput = nil
        sessionStarted = false
        recLock.unlock()

        recTimer?.invalidate()
        recTimer = nil
        recButton.title = "Record"
        
        if #available(macOS 10.14, *) {
            recButton.contentTintColor = nil
        }
        
        popup.isEnabled = true
        resPopup.isEnabled = true

        inp?.markAsFinished()
        w?.finishWriting {
            DispatchQueue.main.async {
                if let url = w?.outputURL {
                    self.statusLabel.stringValue = "Saved \(url.lastPathComponent)"
                }
            }
        }
    }
}
