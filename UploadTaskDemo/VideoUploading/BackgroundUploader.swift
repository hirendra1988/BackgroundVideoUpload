//
//  BackgroundUploader.swift
//  UploadVideoUsingFTP
//
//  Created by Hirendra Sharma on 21/07/24.
//
import Foundation
import UIKit

public class BackgroundUploader: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    static let shared = BackgroundUploader()
    var session: URLSession!
    var index = 0
    var blockCount = 0
    let azureUploader = AzureBlobUploader()
    var chunkSize: Int = 4 * 1024 * 1024
    var chunkFiles = [String]()
    var commitBlobsSuccessfully = false
    var chunksUploadingStarted = false
    
    private override init() {
        super.init()
        let identifier = Bundle.main.bundleIdentifier! + ".backgroundSession"
        let config = URLSessionConfiguration.background(withIdentifier: identifier)
        config.isDiscretionary = true
        config.sessionSendsLaunchEvents = true
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    
    func startUploading() {
        guard let filePath = Bundle.main.url(forResource: "testvideo", withExtension: "mp4") else {
            return
        }
        index = 0
        commitBlobsSuccessfully = false
        chunksUploadingStarted = false
        azureUploader.blobName = appendDateToString(baseString: VideoStrings.currentBlobName)
        Task {
            chunkFiles = await self.saveVideoChunks(fileUrl: filePath)
            let fileData = try Data(contentsOf: filePath)
            await azureUploader.putBlob(blockData: fileData)
        }
    }
    
    func saveVideoChunks(fileUrl: URL) async -> [String] {
        var chunkFiles: [String] = []
        do {
            let fileData = try Data(contentsOf: fileUrl)
            let fileLength = fileData.count
            blockCount = (fileLength + chunkSize - 1) / chunkSize
            for i in 0..<blockCount {
                let start = i * chunkSize
                let end = min((i + 1) * chunkSize, fileLength)
                let chunkData = fileData[start..<end]
                
                let chunkFileName = "video_azure_chunk\(i).mp4"
                let chunkFileUrl = azureUploader.getDocumentsDirectory().appendingPathComponent(chunkFileName)
                try chunkData.write(to: chunkFileUrl, options: .atomic)
                chunkFiles.append(chunkFileName)
            }
        } catch {
            print("Failed to read file or save chunk: \(error)")
        }
        return chunkFiles
    }

    func deleteFile(at fileURL: URL) {
        let fileManager = FileManager.default
        do {
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
                //print("File deleted successfully: \(fileURL)")
            } else {
                print("File does not exist: \(fileURL)")
            }
        } catch {
            print("Error deleting file: \(error.localizedDescription)")
        }
    }

   func deleteAllFilesFromDocumentsDirectory() {
        let fileManager = FileManager.default
        do {
            // Get all files in the document directory
            let fileURLs = try fileManager.contentsOfDirectory(at: azureUploader.getDocumentsDirectory(), includingPropertiesForKeys: nil)
            for fileURL in fileURLs {
                if fileURL.pathExtension == "mp4" || fileURL.pathExtension == "xml" {
                    try fileManager.removeItem(at: fileURL)
                    print("Deleted file: \(fileURL.lastPathComponent)")
                }
            }
            print("Deletion of .mp4 and .xml files completed.")
        } catch {
            print("Error deleting files: \(error.localizedDescription)")
        }
    }

    func appendDateToString(baseString: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "ddMMyyyyHHmmss"
        let currentDate = Date()
        let dateString = dateFormatter.string(from: currentDate)
        let resultString = "\(baseString)_\(dateString).mp4"
        return resultString
    }
    
}

extension BackgroundUploader {
    
    public func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        //print("didCreateTask: \(Date())")
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        print("didReceive")
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        //print("totalBytesExpectedToSend: \(totalBytesExpectedToSend)")
        //let percentage = Double(totalBytesSent) / Double(totalBytesExpectedToSend) * 100
        //print("Data sent: \(percentage)%")
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
       
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("Upload failed with error: \(error.localizedDescription)")
        } else {
            if let httpResponse = task.response as? HTTPURLResponse {
                if task.taskDescription == VideoStrings.getBlobSizeText {
                    if let contentLength = httpResponse.allHeaderFields["Content-Length"] as? String {
                        print("Content-Length: \(contentLength)")
                    } else {
                        print("Content-Length header not found")
                    }
                    return
                }
                print("Upload completed with status code: \(httpResponse.statusCode)")
                if let urlStr = task.response?.url?.absoluteString {
                    if !urlStr.contains("&comp=blocklist") && !urlStr.contains("&comp=block&blockid=") && !chunksUploadingStarted {
                        self.chunksUploadingStarted = true
                        print("******chunksUploadingStarted*********")
                        self.azureUploader.uploadChunksWithFileNames(fileNames: chunkFiles)
                        return
                    }
                }
                if self.commitBlobsSuccessfully {
                    self.commitBlobsSuccessfully = false
                    print("****getBlobSizeAPI****")
                    BackgroundUploader.shared.deleteAllFilesFromDocumentsDirectory()
                    azureUploader.getBlobSizeAPI()
                    return
                }
                if index + 1 == blockCount && !self.commitBlobsSuccessfully {
                    print("****commitBlocks****")
                    self.commitBlobsSuccessfully = true
                    azureUploader.commitBlocks()
                }
                index += 1
                
                if let url = URL(string: task.taskDescription ?? "") {
                    deleteFile(at: url)
                }
            }
        }
    }
    
    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            if let appDelegate = UIApplication.shared.delegate as? AppDelegate,
               let backgroundCompletionHandler = appDelegate.backgroundSessionCompletionHandler {
                appDelegate.backgroundSessionCompletionHandler = nil
                backgroundCompletionHandler()
            }
        }
    }
}
