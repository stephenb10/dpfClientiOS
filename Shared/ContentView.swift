//
//  ContentView.swift
//  Shared
//
//  Created by Stephen Byatt on 26/11/20.
//

import SwiftUI

struct im : Identifiable {
    var id = UUID()
    @State var image : UIImage
}

class Model: ObservableObject, serverDelegate {
    @Published var images = [im]()
    @Published var recevingImages = false
    @Published var sendingImage = false
    @Published var connecting = true
    @Published var didTimeOut = false
    
    let serv = Server()
    
    init() {
        serv.delegate = self
        connecting = true
        _ = Timer.scheduledTimer(timeInterval: 5.0, target: self, selector: #selector(timedOut), userInfo: nil, repeats: false)
        serv.connect()
    }
    
    
    @objc func timedOut() {
        if connecting {
            serv.close()
            connecting = false
            didTimeOut = true
        }
    }
    
    func receivedImage(image: UIImage) {
        self.images.append(im(image: image))
        
        //self.objectWillChange.send()
        print("received image from server")
    }
    
    func finishedReceivingImages() {
        recevingImages = false
        print("received all images")
    }
    
    func received() {
        
    }
    
    func finishedSendingImage(image: UIImage) {
        sendingImage = false
        images.append(im(image: image))
    }
    
    func connected() {
        recevingImages = true
        connecting = false
        serv.receiveAllImages()
    }
    
}

struct ContentView: View {
    @ObservedObject var model = Model()
    @State var showImagePicker: Bool = false
    @State var image: Image? = nil
    @State var uiimage: UIImage? = nil
    @State var showImageFullView = false
    @State var selectedImage = UIImage()
    
    
    
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
                    Text(":( Couldnt find Photo Frame")
                }
                else {
                    LazyVGrid(columns: columns, spacing: 0) {
                        ForEach(model.images, id: \.id) { i in
                            Button {
                                self.selectedImage = i.image
                                showImageFullView = true
                            } label: {
                                Image(uiImage: i.image).resizable().frame(width: 100, height: 100)
                            }
                            .fullScreenCover(isPresented: $showImageFullView) {
                                fullScreenImage(showView: $showImageFullView, image: selectedImage)
                            }
                            
                        }
                    }
                    
                }
            
            }
            
            
        }
    }
}




struct fullScreenImage: View {
    
    @Binding var showView : Bool
    let image: UIImage
    
    var body : some View {
        
        
        VStack {
            Spacer()
            GeometryReader { geo in
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: geo.size.width)
                    .onTapGesture {
                        showView = false
                    }
            }
            Spacer()
        }
        .onAppear(){
            if image.size.width == 0{
                showView = false
            }
            print(image.size)
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

