//
//  BSP.swift
//  DigiFrame
//
//  Created by Stephen Byatt on 1/12/20.
//

import SwiftUI


class Server : NSObject {
    
    weak var delegate: serverDelegate?
    var readingMessage = false
    var inputStream: InputStream!
    var outputStream : OutputStream!
    var address = "localhost"
    var port = 6969
    
    enum requestType:String {
        case transfer = "Transfer-Image"
        case request = "Request-Image"
        case delete = "Delete-Image"
    }
    
    func connect() {
        print("connecting to", address)
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
    
    
    func send(image: UIImage) {
        DispatchQueue.global(qos: .userInitiated).async {
            
            // Convert image to JPEG data and encode in base64
            let imageData = image.jpegData(compressionQuality: 1.0)
            
            let strBase64 = imageData!.base64EncodedString(options: .lineLength64Characters)
            let content = strBase64.data(using: .utf8)!
            
            // Generate BSP headers to transfer image to server
            self.sendHeaders(type: .transfer, contentLength: content.count)
            
            // Send the image data to server
            self.writeall(data: content)
            
            print("Image sent to server")
            
            self.readMessage()
        }
    }
    
    func delete(image: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            self.sendHeaders(type: .delete, imageID: image)
        }
    }
    
    func receiveAllImages(){
        readingMessage = true
        DispatchQueue.global(qos: .userInitiated).async {
            // Generate BSP headers to transfer image to server
            self.sendHeaders(type: .request)
            
            // Read the response
            self.readMessage()
        }
    }
    
    
    
    // Returns JSON data for sending in a message
    private func sendHeaders(type : requestType, contentLength: Int? = nil, imageID : String? = nil) {
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
            jsonDictionary.updateValue(imageID!, forKey: "ImageID")
        }
        
        var headers = Data()
        
        // Convert dictionary to JSON
        do {
            headers = try JSONSerialization.data(withJSONObject: jsonDictionary, options: [])
        } catch {
            print(error.localizedDescription)
        }
        
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
                guard let string = processedMessageString(buffer: buffer, length: bytesRead) else {
                    print("Error converting buffer to string")
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
                //print("\r\((Double(bytesRemaining) / Double(data.count) * 100.0))% transfered")
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
    func finishedSendingImage(image: String)
    func finishedReceivingImages(_ images: [String])
    func received()
    func connected()
    func timedOut()
    func connectionClosed()
}


extension Server: StreamDelegate {
    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case .hasBytesAvailable:
            if !readingMessage {
                print("new message received")
                if self.inputStream.read(UnsafeMutablePointer<UInt8>.allocate(capacity: 1), maxLength: 1) == 0 {
                    delegate?.connectionClosed()
                    
                }
            }
        case .endEncountered:
            delegate?.connectionClosed()
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
            print("Did not connect")
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
    
    
    private func readMessage(stream: InputStream? = nil) {
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
            print(decoded)
            // Work with headers here
            if let headers = decoded as? [String:Any] {
                print("decoded headers", headers)
                if let imageID = headers["ImageID"] {
                    // receivedImageID(imageID)
                    DispatchQueue.main.async {
                        self.delegate?.finishedSendingImage(image: imageID as! String)
                    }
                }
                else if let cl = headers["Content-Length"]{
                    var contentLength = 0
                    if let i = cl as? Int {
                        contentLength = i
                    }
                    else {
                        contentLength = Int(cl as! String)!
                    }

                    var imageIDs = [String]()

                    
                    if contentLength == 0 {
                        print("No images")
                        DispatchQueue.main.async {
                            self.delegate?.finishedReceivingImages(imageIDs)
                            return
                        }
                        return
                    }
                    
                    let content = self.readall(contentLength: contentLength)
                    let jsonContent = try JSONSerialization.jsonObject(with: content.data(using: .utf8)!, options: [])
                    
                    print("raw content", content)
                    print("to json", jsonContent)
                    if let iamgeIDDictionary = jsonContent as? [String:String] {
                        print("dictionary", iamgeIDDictionary)
                        
                        
                        for (index, image) in iamgeIDDictionary {
                            // add imageID to list
                            imageIDs.append(image)
                        }
                        print("finished")
                        
                        DispatchQueue.main.async {
                            self.delegate?.finishedReceivingImages(imageIDs)
                        }
                    }
                }
            }
            
        } catch {
            print("failed decoding json headers")
        }
        
        delegate?.received()
        readingMessage = false
        
        
    }
}
