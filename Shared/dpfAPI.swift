//
//  dpfAPI.swift
//  DigiFrame
//
//  Created by Stephen Byatt on 8/2/21.
//

import SwiftUI
import Alamofire

class dfpAPI {
    weak var delegate: dfpDelegate?
    
    var serverAddress = "https://192.168.1.13:3000/"
    
    var manager = ServerTrustManager(evaluators: ["192.168.1.13": DisabledTrustEvaluator()])
    var session : Session
    
    init() {
        session = Session(serverTrustManager: manager)
    }
    
    func setIP(address: String) {
        serverAddress = "https://\(address):3000/"
        manager = ServerTrustManager(evaluators: [address: DisabledTrustEvaluator()])
        session = Session(serverTrustManager: manager)
    }
    
    func getPhotoIDs() {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
        
            let endpoint = serverAddress + "photos"
            
            session.request(endpoint).responseJSON(completionHandler: { [self] (response) in
                print("Photos endpoint response: ", response)
                switch response.result {
                
                case .success(_):
                    if let json = JSONData(from: response.data) {
                        let imageIDs = json["photos"] as! [String]
                        print(imageIDs)
                        delegate?.didReceiveImageIDs(imageIDs)
                    }
                    
                case .failure(let error):
                    if let underlyingError = error.underlyingError {
                        if let urlError = underlyingError as? URLError {
                            switch urlError.code {
                            case .notConnectedToInternet:
                                delegate?.didCloseConnection()
                            case .cannotConnectToHost:
                                delegate?.didCloseConnection()
                            default:
                                print("Unmanaged error")
                                print(error)
                            }
                        }
                    }
                    
                }
            })
        }
    }
    
    func send(image: UIImage) {
        print("Preparing image to send")
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            // Convert image to JPEG data and encode in base64
            let imageData = image.jpegData(compressionQuality: 1.0)
            let strBase64 = imageData!.base64EncodedString(options: .lineLength64Characters)
            
            let endpoint = serverAddress + "photos"
            
            let parameters: [String: Any] = [
                "imageData" : strBase64
            ]
            
            print(endpoint, "sending post ")
            
            self.session.request(endpoint, method: .post, parameters: parameters, encoding: JSONEncoding.default)
                .uploadProgress(closure: { (progress) in
                    print("\(Int(progress.fractionCompleted * 100))%")
                    delegate?.progressSent(value: progress.fractionCompleted)
                })
                .responseJSON { (response) in
                    if let status = response.response?.statusCode {
                        print("Receive resposne with status: ", status)
                        if (200..<300).contains(status) {
                            if let json = JSONData(from: response.data) {
                                let id = json["photoID"] as! String
                                print(id)
                                delegate?.didSendImage(imageID: id)
                            }
                        }
                    }
                }
            print("Finished sending photo")

        }
    }
    
    func deleteImage(withName image: String) {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let endpoint = serverAddress + "photos/"+image
            
            self.session.request(endpoint, method: .delete, encoding: JSONEncoding.default).responseJSON { (response) in
                print("Photos endpoint response: ", response)
                
                if let status = response.response?.statusCode {
                    print("Receive resposne with status: ", status)
                }
            }
        }
    }
    
    private func JSONData(from d : Data?) -> [String:Any]? {
        guard let data = d else {return nil}
        
        do {
            if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                return json
            }
        } catch let error as NSError {
            print("Failed to load: \(error.localizedDescription)")
        }
        return nil
    }
}

protocol dfpDelegate: class {
    func didSendImage(imageID: String)
    func didReceiveImageIDs(_ images: [String])
    func didCloseConnection()
    func progressSent(value : Double)
}
