//
//  ContentView.swift
//  Shared
//
//  Created by Stephen Byatt on 26/11/20.
//

import SwiftUI
import SDWebImageSwiftUI

struct im : Identifiable {
    var id = UUID()
    var filename : String
}

class Model: ObservableObject, serverDelegate {
    
    @Published var images = [im]()
    @Published var recevingImages = false
    @Published var sendingImage = false
    @Published var connecting = true
    @Published var didTimeOut = false
    
    let ssdp = SSDP()
    let serv = Server()
    
    init() {
        serv.delegate = self
        tryConnect()
    }
    
    
    
    // TO DO
    // Keep track of retry attempts to connect and then prompt to re run SSDP again
    // Check if connection has been interupted
    
    func tryConnect(){
        connecting = true
        
        let defaults = UserDefaults.standard
        
        // If we know the IP address already
        if let address = defaults.value(forKey: "ipAddress") {
            print(address, "saved")
            connect(to: address as! String)
            return
        }
        // Search for IP address
        
        var address : String? = nil
        
        DispatchQueue.global(qos: .userInitiated).async {
            address = self.ssdp.discover()
            DispatchQueue.main.async {
                if address != nil {
                    print(address, "discovered")
                    defaults.setValue(address, forKey: "ipAddress")
                    self.connect(to: address!)
                    return
                }
                else {
                    print("failed to find")
                    
                    // Could not find IP address
                    self.connecting = false
                    self.didTimeOut = true
                }
                
            }
            
            
        }
        
        
    }
    
    func connect(to address: String) {
        print("starting up tcp connection")
        _ = Timer.scheduledTimer(timeInterval: 5.0, target: self, selector: #selector(timedOut), userInfo: nil, repeats: false)
        
        serv.address = address
        print("set the socket address to", address)
        self.serv.connect()
        
        print("socket connection finished")
    }
    
    
    @objc func timedOut() {
        if connecting {
            serv.close()
            connecting = false
            didTimeOut = true
        }
    }
    
    func finishedReceivingImages(_ images: [String]) {
        recevingImages = false
        for s in images {
            self.images.append(im(filename: s))
        }
        print("received all images")
    }
    
    func received() {
        
    }
    
    func finishedSendingImage(image: String) {
        sendingImage = false
        images.append(im(filename: image))
    }
    
    func connected() {
        print("connected successfuly")
        recevingImages = true
        connecting = false
        didTimeOut = false
        serv.receiveAllImages()
    }
    
}

struct ContentView: View {
    @ObservedObject var model = Model()
    @State var showImagePicker: Bool = false
    @State var image: Image? = nil
    @State var uiimage: UIImage? = nil
    @State var showImageFullView = false
    @State var selectedImage = String()
    
    
    
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        ScrollView {
            
            Button(action: {
                self.showImagePicker.toggle()
                print("showing image picker", self.showImagePicker)
            }) {
                Text("Show image picker")
            }.sheet(isPresented: $showImagePicker) {
                ImagePicker(sourceType: .photoLibrary) { image in
                    self.uiimage = image
                    self.image = Image(uiImage: image)
                    
                }
            }
            
            image?.resizable().frame(width: 100, height: 100)
            
            Button("Send to server") {
                if(image != nil) {
                    self.model.sendingImage = true
                    model.serv.send(image: uiimage!)
                }
            }
            Divider()
            
            if(self.model.recevingImages ||  self.model.sendingImage || self.model.connecting){
                ProgressView()
            }
            
            if !self.model.connecting {
                
                if self.model.didTimeOut {
                    Text("Couldnt find Photo Frame :(")
                    Button("Retry"){
                        self.model.tryConnect()
                    }
                }
                else {
                    
                    if model.images.count > 0 {
                    LazyVGrid(columns: columns, spacing: 0) {
                        ForEach(model.images) { i in
                            let address = "http://\(self.model.serv.address)/\(i.filename)"
                            AnimatedImage(url: URL(string: address))
                                .resizable()
                                .placeholder(UIImage(systemName: "photo"))
                                .indicator(.activity)
                                .transition(.fade(duration: 0.5))
                                .frame(width: 100, height: 100)
                                .onTapGesture {
                                    self.selectedImage = i.filename
                                    showImageFullView = true
                                }
                                .fullScreenCover(isPresented: $showImageFullView) {
                                    fullScreenImage(showView: $showImageFullView, model: model, imageID: selectedImage)
                                }
                            
                        }
                    }
                    }
                    else {
                        Text("No images yet")
                    }
                    
                    
                    
                }
                
            }
            
        }
    }
}

struct fullScreenImage: View {
    
    @Binding var showView : Bool
    @ObservedObject var model : Model
    let imageID: String
    
    var body : some View {
        VStack {
            GeometryReader { geo in
                let address = "http://\(self.model.serv.address)/\(imageID)"
                WebImage(url: URL(string: address))
                    .resizable()
                    .placeholder(Image(systemName: "photo"))
                    .indicator(.activity)
                    .transition(.fade(duration: 0.5))
                    .aspectRatio(contentMode: .fit)
                    .frame(width: geo.size.width)
                    .onTapGesture {
                        showView = false
                    }
            }
            Button("Delete") {
                self.model.serv.delete(image: imageID)
                
                var ii = 0
                for i in self.model.images {
                    if i.filename == imageID
                    {
                        break
                    }
                    ii += 1
                }
                self.model.images.remove(at: ii)
                showView = false
            }
        }
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    
    @Environment(\.presentationMode)
    private var presentationMode
    
    let sourceType: UIImagePickerController.SourceType
    let onImagePicked: (UIImage) -> Void
    
    final class Coordinator: NSObject,
                             UINavigationControllerDelegate,
                             UIImagePickerControllerDelegate {
        
        @Binding
        private var presentationMode: PresentationMode
        private let sourceType: UIImagePickerController.SourceType
        private let onImagePicked: (UIImage) -> Void
        
        init(presentationMode: Binding<PresentationMode>,
             sourceType: UIImagePickerController.SourceType,
             onImagePicked: @escaping (UIImage) -> Void) {
            _presentationMode = presentationMode
            self.sourceType = sourceType
            self.onImagePicked = onImagePicked
        }
        
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            let uiImage = info[UIImagePickerController.InfoKey.originalImage] as! UIImage
            onImagePicked(uiImage)
            presentationMode.dismiss()
            
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            presentationMode.dismiss()
        }
        
    }
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(presentationMode: presentationMode,
                           sourceType: sourceType,
                           onImagePicked: onImagePicked)
    }
    
    func makeUIViewController(context: UIViewControllerRepresentableContext<ImagePicker>) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController,
                                context: UIViewControllerRepresentableContext<ImagePicker>) {
        
    }
    
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

