//
//  CapturePreviewView.swift
//  VideoXRay
//
//  Created by Stanly Shiyanovskiy on 22.10.2020.
//

import AVFoundation
import UIKit

public final class CapturePreviewView: UIView {
    
    public override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }

}
