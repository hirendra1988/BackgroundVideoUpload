//
//  ViewController.swift
//  UploadTaskDemo
//
//  Created by Hirendra Sharma on 23/07/24.
//

import UIKit

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        BackgroundUploader.shared.deleteAllFilesFromDocumentsDirectory()
        print(getDocumentsDirectory())
    }

    @IBAction func startUploading() {
        BackgroundUploader.shared.startUploading()
    }
    
    func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
}
