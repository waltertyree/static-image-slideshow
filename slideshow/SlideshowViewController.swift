//
//  ViewController.swift
//  slideshow
//
//  Created by Walter Tyree on 1/11/22.
//

import UIKit
import AVFoundation
import AVKit
import os
import CoreImage.CIFilterBuiltins


class SlideshowViewController: UIViewController {

  @IBOutlet var spinner: UIActivityIndicatorView!
  @IBOutlet var playerView: UIView!

  var player: AVPlayer?
  var outputSlideshow: AVVideoComposition? {
    didSet {
      if let outputSlideshow = outputSlideshow {
        DispatchQueue.main.async {
          try? self.export(self.outputMovie!, composition: outputSlideshow)
          let item = AVPlayerItem(asset: self.outputMovie!)
          item.videoComposition = outputSlideshow
          self.player = AVPlayer(playerItem: item)

          let playerLayer = AVPlayerLayer(player: self.player)
          playerLayer.frame = self.playerView.layer.bounds
          playerLayer.videoGravity = .resizeAspect

          self.playerView.layer.addSublayer(playerLayer)

          self.player?.play()
        }
      }
    }
  }
  var outputMovie: AVAsset? {
    didSet {
      if let outputMovie = outputMovie {
        self.createComposition(outputMovie)
      }
    }
  }




  @IBAction func generateSlideShow(_ sender: Any) {
    do
    {
      try  createFilmstrip(CIColor.gray, duration: 9, completion: storeURL())

    } catch (let error) {
      print(error.localizedDescription)
    }
  }

  fileprivate func storeURL() -> (URL) -> Void {
    return {[weak self] url in
      let asset = AVAsset(url: url)
      self?.outputMovie = asset
    }
  }

  fileprivate func fetchSlide(forTime t: CMTime) -> CIImage? {
    let threeSeconds = CMTimeMakeWithSeconds(3, preferredTimescale: 300)
    let firstSlideRange = CMTimeRangeMake(start: CMTime.zero, duration: threeSeconds)
    let secondSlideRange = CMTimeRangeMake(start: threeSeconds, duration: threeSeconds)
    if firstSlideRange.containsTime(t) {
      return CIImage(image: UIImage(named: "IMG_2705")!)
    } else if secondSlideRange.containsTime(t) {
      return CIImage(image: UIImage(named: "IMG_2591")!)
    } else {
      return CIImage(image: UIImage(named: "IMG_2558")!)
    }
  }

  func createComposition(_ asset: AVAsset) {
    let slideshowComposition = AVVideoComposition(asset: asset) {[weak self] request in
      guard let self = self else { return }

      let slide = self.fetchSlide(forTime: request.compositionTime)

      let compose = CIFilter.sourceOverCompositing()
      compose.backgroundImage = request.sourceImage
      compose.inputImage = slide?.transformed(by: CGAffineTransform(translationX: request.compositionTime.seconds * 50, y: 0))

      request.finish(with: compose.outputImage!, context: nil)
    }

    self.outputSlideshow = slideshowComposition
  }


  func export(_ asset: AVAsset, composition: AVVideoComposition) throws {

    guard let outputMovieURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("fancy_export.mov") else {
      throw ConstructionError.invalidURL
    }

    //delete any old file
    do {
      try FileManager.default.removeItem(at: outputMovieURL)
    } catch {
      print("Could not remove file \(error.localizedDescription)")
    }

    //create exporter
    let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality)

    //configure exporter
    exporter?.videoComposition = composition
    exporter?.outputURL = outputMovieURL
    exporter?.outputFileType = .mov

    //export!
    exporter?.exportAsynchronously(completionHandler: { [weak exporter] in
      DispatchQueue.main.async {
        if let error = exporter?.error {
          Logger().error("failed \(error.localizedDescription)")
        } else {
          Logger().info("Fancy movie exported: \(outputMovieURL)")
        }
      }

    })
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    // Do any additional setup after loading the view.
  }

  func createFilmstrip(_ bgColor: CIColor, duration: Int, completion: @escaping (URL)->Void) throws  {
    let staticImage = CIImage(color: bgColor).cropped(to: CGRect(x: 0, y: 0, width: 960, height: 540))

    var pixelBuffer: CVPixelBuffer?
    let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
         kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary
    let width:Int = Int(staticImage.extent.size.width)
    let height:Int = Int(staticImage.extent.size.height)
    CVPixelBufferCreate(kCFAllocatorDefault,
                        width,
                        height,
                        kCVPixelFormatType_32BGRA,
                        attrs,
                        &pixelBuffer)

    let context = CIContext()
    context.render(staticImage, to: pixelBuffer!)



    //generate a file url to store the video. some_image.jpg becomes some_image.mov
    guard let outputMovieURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("background.mov") else {
      throw ConstructionError.invalidURL
    }

    //delete any old file
    do {
      try FileManager.default.removeItem(at: outputMovieURL)
    } catch {
      print("Could not remove file \(error.localizedDescription)")
    }

    //create an assetwrite instance
    guard let assetwriter = try? AVAssetWriter(outputURL: outputMovieURL, fileType: .mov) else {
      abort()
    }

    //generate 960x540 settings
    let settingsAssistant = AVOutputSettingsAssistant(preset: .preset960x540)?.videoSettings

    //create a single video input
    let assetWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: settingsAssistant)

    //create an adaptor for the pixel buffer
    let assetWriterAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: assetWriterInput, sourcePixelBufferAttributes: nil)

    //add the input to the asset writer
    assetwriter.add(assetWriterInput)

    //begin the session
    assetwriter.startWriting()
    assetwriter.startSession(atSourceTime: CMTime.zero)

    //determine how many frames we need to generate
    let framesPerSecond = 30
    let totalFrames = duration * framesPerSecond
    var frameCount = 0

    while frameCount < totalFrames {
      if assetWriterInput.isReadyForMoreMediaData {
        let frameTime = CMTimeMake(value: Int64(frameCount), timescale: Int32(framesPerSecond))
        //append the contents of the pixelBuffer at the correct ime
        assetWriterAdaptor.append(pixelBuffer!, withPresentationTime: frameTime)
        frameCount+=1
      }
    }

    //close everything
    assetWriterInput.markAsFinished()
    assetwriter.finishWriting {
      pixelBuffer = nil
      completion(outputMovieURL)
      //outputMovieURL now has the video
      Logger().info("Finished video location: \(outputMovieURL)")
    }
  }

}

