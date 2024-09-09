//
//  AzureBlobUploader.swift
//  UploadTaskDemo
//
//  Created by Hirendra Sharma on 04/08/24.
//

import Foundation
import AZSClient
import CommonCrypto
import CryptoKit

class AzureBlobUploader {
    private var sasToken: String = ""
    var blockIds: [String] = []
    var blobName = ""

    init() {
        self.sasToken = generateAuthorizationHeader()
    }

    func uploadChunksWithFileNames(fileNames: [String]) {
        blockIds.removeAll()
        for (index, fileName) in fileNames.enumerated() {
            let blockId = String(format: "%06d", index)
            let blockIdBase64 = base64EncodeBlockID(blockID: blockId)
            blockIds.append(blockIdBase64)
            let fileUrl = getFileURL(fromFilename: fileName)
            Task {
                await self.uploadChunk(chunkUrl: fileUrl, blockId: blockIdBase64)
            }
        }
    }
    
    func putBlob(blockData: Data) async {
        let urlString = "https://\(VideoStrings.accountName).blob.core.windows.net/\(VideoStrings.containerName)/\(blobName)?\(sasToken)"
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "PUT"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("BlockBlob", forHTTPHeaderField: "x-ms-blob-type")
        request.addValue("2019-12-12", forHTTPHeaderField: "x-ms-version")
        request.setValue("\(blockData.count)", forHTTPHeaderField: "Content-Length")
        let dataTask = BackgroundUploader.shared.session.dataTask(with: request)
        dataTask.resume()
    }
    
    private func uploadChunk(chunkUrl: URL, blockId: String) async {
        let urlString = "https://\(VideoStrings.accountName).blob.core.windows.net/\(VideoStrings.containerName)/\(blobName)?\(sasToken)&comp=block&blockid=\(blockId)"
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "PUT"
        do {
            let chunkData = try Data(contentsOf: chunkUrl)
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            request.setValue("\(chunkData.count)", forHTTPHeaderField: "Content-Length")
            request.setValue("BlockBlob", forHTTPHeaderField: "x-ms-blob-type")
            request.addValue("2019-12-12", forHTTPHeaderField: "x-ms-version")
            
            let uploadTask = BackgroundUploader.shared.session.uploadTask(with: request, fromFile: chunkUrl)
            uploadTask.taskDescription = chunkUrl.absoluteString
            uploadTask.resume()
            
        } catch {
            print("Failed to read chunk data: \(error)")
        }
    }
    
    func commitBlocks() {
        let urlString = "https://\(VideoStrings.accountName).blob.core.windows.net/\(VideoStrings.containerName)/\(blobName)?\(sasToken)&comp=blocklist"
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "PUT"
        
        var xmlString = "<?xml version=\"1.0\" encoding=\"utf-8\"?><BlockList>"
        for blockId in blockIds {
            xmlString += "<Uncommitted>\(blockId)</Uncommitted>"
        }
        xmlString += "</BlockList>"
        let blockListData = xmlString.data(using: .utf8)
        
        let fileURL = getDocumentsDirectory().appendingPathComponent("data.xml")
        do {
            try blockListData?.write(to: fileURL)
            //print("File saved at: \(fileURL)")
        } catch {
            print("Error saving file: \(error)")
        }
        
        request.setValue("\(blockListData?.count ?? 0)", forHTTPHeaderField: "Content-Length")
        request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        request.addValue("2019-12-12", forHTTPHeaderField: "x-ms-version")
        
        let uploadTask = BackgroundUploader.shared.session.uploadTask(with: request, fromFile: fileURL)
        uploadTask.taskDescription = fileURL.absoluteString
        uploadTask.resume()
    }

    func getBlobSizeAPI() {
        let urlString = "https://\(VideoStrings.accountName).blob.core.windows.net/\(VideoStrings.containerName)/\(blobName)?\(sasToken)"
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "HEAD"
        //request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        request.addValue("2019-12-12", forHTTPHeaderField: "x-ms-version")

        let testData = "test".data(using: .utf8)
        let fileURL = getDocumentsDirectory().appendingPathComponent("testData.xml")
        do {
            try testData?.write(to: fileURL)
        } catch {
            print("Error saving testData: \(error)")
        }
        //let uploadTask = BackgroundUploader.shared.session.uploadTask(with: request, fromFile: fileURL)
        let uploadTask = BackgroundUploader.shared.session.downloadTask(with: request)
        uploadTask.taskDescription = VideoStrings.getBlobSizeText
        uploadTask.resume()
    }

    func generateAuthorizationHeader() -> String {
        let date = Date()
        let expiry = date.addingTimeInterval(120 * 60)
        let aZSSharedAccessAccountParameters = AZSSharedAccessAccountParameters()
        let permissions = AZSSharedAccessPermissions.all
        let resourceType = AZSSharedAccessResourceTypes.all
        let sertvices = AZSSharedAccessServices.all
        aZSSharedAccessAccountParameters.permissions = permissions
        aZSSharedAccessAccountParameters.resourceTypes = resourceType
        aZSSharedAccessAccountParameters.services = sertvices
        aZSSharedAccessAccountParameters.sharedAccessStartTime = date
        aZSSharedAccessAccountParameters.sharedAccessExpiryTime = expiry
        let storageAccount = try! AZSCloudStorageAccount.init(fromConnectionString: VideoStrings.storageConnectionString)
        let sasToken = try! storageAccount.createSharedAccessSignature(with: aZSSharedAccessAccountParameters)
        return sasToken
    }
    
    func base64EncodeBlockID(blockID: String) -> String {
        let blockIDData = blockID.data(using: .utf8)!
        return blockIDData.base64EncodedString()
    }
    
    func getFileURL(fromFilename filename: String) -> URL {
        return getDocumentsDirectory().appendingPathComponent(filename)
    }
    
    func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
}
