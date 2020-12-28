//
//  BSP.swift
//  DigiFrame
//
//  Created by Stephen Byatt on 1/12/20.
//

import SwiftUI

class ImageCache {
    var cache = NSCache<NSString, UIImage>()
    
    func get(forKey key : String) -> UIImage? {
        return cache.object(forKey: NSString(string: key))
    }
    
    func set(forKey key : String, image : UIImage) {
        cache.setObject(image, forKey: NSString(string: key))
    }
}

extension ImageCache {
    private static var imageCache = ImageCache()
    static func getImageCache() -> ImageCache {
        return imageCache
    }
}


class Server : NSObject {
    
    weak var delegate: serverDelegate?
    var readingMessage = false
    var inputStream: InputStream!
    var outputStream : OutputStream!
    var imageCache = ImageCache.getImageCache()
    var address = "192.168.1.14"
    var port = 6969
    
    enum requestType:String {
        case transfer = "Transfer-Image"
        case request = "Request-Image"
    }
    
    func connect() {
        var readStream : Unmanaged<CFReadStream>?
        var writeStream : Unmanaged<CFWriteStream>?
        
        CFStreamCreatePairWithSocketToHost(kCFAllocatorDefault, address as CFString, UInt32(port), &readStream, &writeStream)
        
        inputStream = readStream!.takeRetainedValue()
        outputStream = writeStream?.takeRetainedValue()
        
        inputStream.delegate = self
        
        inputStream.schedule(in: .current, forMode: .common)
        outputStream.schedule(in: .current, forMode: .common)
        
        inputStream.open()
        outputStream.open()
        
    }
    
    // Returns JSON data
    private func generateHeaders(type : requestType, imageID: String? = nil, contentLength: Int? = nil) -> Data {
        // Dictionary to convert to JSON
        var jsonDictionary = [String:String]()
        jsonDictionary.updateValue(type.rawValue, forKey: "Request-Type")
        
        if contentLength != nil{
            jsonDictionary.updateValue(String(contentLength!), forKey: "Content-Length")
        }
        else {
            jsonDictionary.updateValue("0", forKey: "Content-Length")
            
        }
        if imageID != nil {
            jsonDictionary.updateValue(imageID!, forKey: "Image-ID")
        }
        
        var headers = Data()
        
        // Convert dictionary to JSON
        do {
            headers = try JSONSerialization.data(withJSONObject: jsonDictionary, options: [])
        } catch {
            print(error.localizedDescription)
        }
        
        return headers
    }
    
    
    func send(image: UIImage) {
        DispatchQueue.global(qos: .userInitiated).async {
            
            // Convert image to JPEG data and encode in base64
            let imageData = image.jpegData(compressionQuality: 1.0)
            
            let strBase64 = imageData!.base64EncodedString(options: .lineLength64Characters)
            let content = strBase64.data(using: .utf8)!
            
            // Generate BSP headers to transfer image to server
            let headers = self.generateHeaders(type: .transfer, contentLength: content.count)
            
            // First 3 bytes of message specify the size of the headers
            // Encode data to be sent with utf8
            let data = String(String(format: "%03d", headers.count)).data(using: .utf8)!
            
            // Send the header size to the server
            data.withUnsafeBytes {
                guard let pointer = $0.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    print("Error")
                    return
                }
                self.outputStream.write(pointer, maxLength: data.count)
            }
            
            // Send the headers to the server
            headers.withUnsafeBytes {
                guard let pointer = $0.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    print("Error")
                    return
                }
                self.outputStream.write(pointer, maxLength: headers.count)
            }
            
            // Send the image data to server
            self.writeall(data: content)
            
            print("Image sent to server")
            
            //TO DO
            // Change readmessage to return json headers then add that id to the list of all image ID's
            self.readMessage { (imageID) in
                // cache the imageID here
                print(imageID)
                DispatchQueue.main.async {
                    self.imageCache.set(forKey: imageID, image: image)
                    self.delegate?.finishedSendingImage(image: image)
                    
                }
                print("!!!~~~~~~~~ Cached image~~!!!!!")
                
            }
        }
        
        
    }
    
    func receiveAllImages(){
        readingMessage = true
        DispatchQueue.global(qos: .userInitiated).async {
            
            // Generate BSP headers to transfer image to server
            let headers = self.generateHeaders(type: .request)
            
            // First 3 bytes of message specify the size of the headers
            // Encode data to be sent with utf8
            let data = String(String(format: "%03d", headers.count)).data(using: .utf8)!
            
            // Send the header size to the server
            data.withUnsafeBytes {
                guard let pointer = $0.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    print("Error")
                    return
                }
                self.outputStream.write(pointer, maxLength: data.count)
            }
            
            // Send the headers to the server
            headers.withUnsafeBytes {
                guard let pointer = $0.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    print("Error")
                    return
                }
                self.outputStream.write(pointer, maxLength: headers.count)
            }
            
            // Receive dictionary with all the image ID's
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 3)
            
            var numberOfBytesRead = 0
            
            numberOfBytesRead = self.inputStream.read(buffer, maxLength: 3)
            guard let headerSize = self.processedMessageString(buffer: buffer, length: numberOfBytesRead) else {
                self.readingMessage = false
                return
            }
            
            print("header size", headerSize)
            
            let size = Int(headerSize) ?? 0
            let headerBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
            numberOfBytesRead = self.inputStream.read(headerBuffer, maxLength: size)
            print("read header of bytes", numberOfBytesRead)
            
            
            // JSON Dictionary of all image ID's in format of [String:String] [index:imageID]
            let jsonHeaders = self.readall(contentLength: size)
            
            print("headers", jsonHeaders)
            
            do {
                let decoded = try JSONSerialization.jsonObject(with: jsonHeaders.data(using: .utf8)!, options: [])
                // Work with headers here
                if let headers = decoded as? [String:String] {
                    // Dictionary format int : string
                    // list of all imageID's
                   
                    for (index, imageID) in headers {
                        // add ID to a list of all image ID's
                    }
                    
                    /// NOTIFY DELEGATE RECEIVED ALL IMAGE ID's
                    
                }
                
            } catch {
                
            }
            
        }
    }
    
    private func readall(contentLength: Int) -> String {
        var bytesRemaining = contentLength
        var bytesRead = 0
        var data = ""
        // Loop through until all bytes are written
        repeat{
            // Write bytes to stream
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bytesRemaining)
            bytesRead = inputStream.read(buffer, maxLength: bytesRemaining)
            
            if bytesRead > 0
            {
                
                guard let string = String(
                        bytesNoCopy: buffer,
                        length: bytesRead,
                        encoding: .utf8,
                        freeWhenDone: true)
                else {
                    return String()
                }
                
                data += string
                
                bytesRemaining -= bytesRead
                
                if bytesRemaining == 0
                {
                    return data
                }
            }
            else
            {
                return String()
            }
        } while true
    }
    
    
    private func writeall(data : Data) {
        var remainingData = data
        var bytesRemaining = data.count
        var bytesWritten = 0
        
        // Loop through until all bytes are written
        repeat{
            // Write bytes to stream
            remainingData.withUnsafeBytes
            {
                guard let pointer = $0.baseAddress?.assumingMemoryBound(to: UInt8.self) else
                {
                    print("Error")
                    return
                }
                
                bytesWritten = outputStream.write(pointer, maxLength: bytesRemaining)
            }
            
            if bytesWritten > 0
            {
                
                bytesRemaining -= bytesWritten
                
                if bytesRemaining == 0
                {
                    return
                }
                
                remainingData = remainingData.advanced(by: bytesWritten)
                print("\r\((Double(bytesRemaining) / Double(data.count) * 100.0))% transfered")
                
            }
            else
            {
                print("Error writuing data")
                return
            }
        } while true
    }
    
    func close(){
        inputStream.close()
        outputStream.close()
    }
}

protocol serverDelegate: class {
    func receivedImage(image: UIImage)
    func finishedSendingImage(image: UIImage)
    func finishedReceivingImages()
    func received()
    func connected()
    func timedOut()
}


extension Server: StreamDelegate {
    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case .hasBytesAvailable:
            if !readingMessage {
                print("new message received")
                //readMessage(stream: aStream as! InputStream)
            }
        case .endEncountered:
            print("end encountered")
        case .errorOccurred:
            print("error occurred")
            delegate?.timedOut()
        case .hasSpaceAvailable:
            print("has space available")
        case .openCompleted:
            print("Connected successfuly")
            delegate?.connected()
        case .errorOccurred:
            print("Did not connected")
        default:
            print("some other event...")
        }
    }
    
    private func processedMessageString(_ stream: InputStream? = nil, buffer: UnsafeMutablePointer<UInt8>, length: Int) -> String?{
        if stream != nil {
            if length < 0, let error = stream?.streamError {
                print(error)
                return nil
            }
        }
        
        guard let string = String(
                bytesNoCopy: buffer,
                length: length,
                encoding: .utf8,
                freeWhenDone: true)
        else {
            print("Could not convert buffer to string")
            return nil
        }
        return string
    }
    
    // TO DO
    // Change this to read Headers and return a json dictionary
    
    private func readMessage(stream: InputStream? = nil, receivedImageID: (_ imageID: String) -> () = {_ in }) {
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 3)
        
        readingMessage = true
        
        var numberOfBytesRead = 0
        
        numberOfBytesRead = self.inputStream.read(buffer, maxLength: 3)
        guard let headerSize = self.processedMessageString(buffer: buffer, length: numberOfBytesRead) else {
            self.readingMessage = false
            return
        }
        print("header size", headerSize)
        
        let size = Int(headerSize) ?? 0
        let headerBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        numberOfBytesRead = self.inputStream.read(headerBuffer, maxLength: size)
        print("read header of bytes", numberOfBytesRead)
        
        guard let jsonHeaders = self.processedMessageString(buffer: headerBuffer, length: numberOfBytesRead) else {
            self.readingMessage = false
            print("error processing json header")
            return
        }
        
        print("headers", jsonHeaders)
        
        do {
            let decoded = try JSONSerialization.jsonObject(with: jsonHeaders.data(using: .utf8)!, options: [])
            // Work with headers here
            if let headers = decoded as? [String:String] {
                
                if let imageID = headers["ImageID"] {
                    receivedImageID(imageID)
                }
            }
            
        } catch {
            
        }
        
        delegate?.received()
        readingMessage = false
        
        
    }
}
