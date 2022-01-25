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

enum ConstructionError: Error {
  case invalidImage, invalidURL
}

class SimpleSlideGenerator: UIViewController {

  @IBOutlet var playerView: UIView!
  @IBOutlet var spinner: UIActivityIndicatorView!
  var movieList = [URL]()
  var transformsList = [CMTimeRange]()
  var exporter: AVAssetExportSession?
  var outputMovie: AVAsset? {
    didSet {
      DispatchQueue.main.async {
        [weak self] in
        guard let self = self else { return }
            if let outputMovie = self.outputMovie {
        let player = AVPlayer(playerItem: AVPlayerItem(asset: outputMovie))
          self.playerView.layer.sublayers?.removeAll()
        let playerLayer = AVPlayerLayer(player: player)
          playerLayer.frame = self.playerView.layer.bounds
        playerLayer.videoGravity = .resizeAspect

          self.playerView.layer.addSublayer(playerLayer)

          self.spinner.stopAnimating()
          player.play()
            }
      }
  }
  }

  @IBAction func generateSlides(_ sender: Any) {
    if self.spinner.isAnimating {
      //don't let them press the button twice
      return
    }
    self.movieList.removeAll()
    DispatchQueue.main.async {
    self.spinner.startAnimating()
    }

    do
    {
      try  createFilmstrip("IMG_2705.jpeg", duration: 3, completion: storeURL())
      try  createFilmstrip("IMG_2558.jpeg", duration: 3, completion: storeURL())
      try createFilmstrip("IMG_2591.jpeg", duration: 3, completion: storeURL())

    } catch (let error) {
      print(error.localizedDescription)
    }


  }
  func addURLToMovieList(_ url: URL) -> Void {
    self.movieList.append(url)
    if self.movieList.count == 3 {
      stitchAndPlay()
    }
  }

  func stitchAndPlay() {
    let movie = AVMutableComposition()
    let videoTrack = movie.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)

    var currentDuration = movie.duration
    do {
      for item in self.movieList {

        let stripMovie = AVURLAsset(url: item)
        let stripRange = CMTimeRangeMake(start: CMTime.zero, duration: stripMovie.duration)
        let stripVideoTrack = stripMovie.tracks(withMediaType: .video).first!

        try videoTrack?.insertTimeRange(stripRange, of: stripVideoTrack, at: currentDuration)

        videoTrack?.preferredTransform = stripVideoTrack.preferredTransform
        currentDuration = movie.duration
      }
      let audioTrack = movie.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

      let soundtrack = AVAsset(url: Bundle.main.url(forResource: "Yippee", withExtension: "caf")!)
      let soundtrackRange = CMTimeRangeMake(start: CMTime.zero, duration: soundtrack.duration)


      try audioTrack?.insertTimeRange(soundtrackRange, of: soundtrack.tracks(withMediaType: .audio).first!, at: CMTime.zero)
    } catch (let error) {
      print(error.localizedDescription)
    }

    self.outputMovie = movie.copy() as! AVComposition
  }

  fileprivate func storeURL() -> (URL) -> Void {
    return {[weak self] url in
      self?.addURLToMovieList(url)
    }
  }


  func createFilmstrip(_ imageName: String, duration: Int, completion: @escaping (URL)->Void) throws  {
    guard let uikitImage = UIImage(named: imageName), let staticImage = CIImage(image: uikitImage) else {
      throw ConstructionError.invalidImage
    }
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

    guard let imageNameRoot = imageName.split(separator: ".").first, let outputMovieURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("\(imageNameRoot).mov") else {
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

    //generate 1080p settings
    let settingsAssistant = AVOutputSettingsAssistant(preset: .preset1920x1080)?.videoSettings

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
      //outputMovieURL now has the video
      completion(outputMovieURL)
      Logger().info("Finished video location: \(outputMovieURL)")
    }
  }
}

