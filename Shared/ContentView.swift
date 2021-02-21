//
//  ContentView.swift
//  Shared
//
//  Created by Stephen Byatt on 26/11/20.
//
import SwiftUI
import SDWebImageSwiftUI

struct dpfPhoto : Identifiable {
    var id = UUID()
    var filename : String
}

class Model: ObservableObject, dfpDelegate {
    
    @Published var images = [dpfPhoto]()
    @Published var sendingImage = false
    @Published var connectionFailed = false
    @Published var sendingProgress : Double = 0
    @Published var selectedImage = String()
    
    let ssdp = SSDP()
    let dfp = dfpAPI()
    
    init() {
        dfp.delegate = self
        tryConnect()
    }
    
    func tryConnect(){
        let defaults = UserDefaults.standard
        
        // If we know the IP address already
        if let address = defaults.value(forKey: "ipAddress") {
            print(address, "saved")
            dfp.setIP(address: address as! String)
        }
        else {
            // Discover Photo Frame
            var address : String? = nil
            DispatchQueue.global(qos: .userInitiated).async {
                address = self.ssdp.discover()
                DispatchQueue.main.async { [self] in
                    if address != nil {
                        print(address!, "discovered")
                        defaults.setValue(address, forKey: "ipAddress")
                        dfp.setIP(address: address!)
                    }
                    else {
                        print("failed to find")
                        // Could not find IP address
                        self.connectionFailed = true
                    }
                }
            }
        }
        
        
        dfp.getPhotoIDs()
        if images.count > 0
        {
            selectedImage = images.first!.filename
        }
        
    }
    
    func delete(image imageID : String){
        self.dfp.deleteImage(withName: imageID)
        
        // zip range and images into one loop with index as well
        var ii = 0
        for i in images {
            if i.filename == imageID
            {
                break
            }
            ii += 1
        }
        self.images.remove(at: ii)
    }
    
    func didSendImage(imageID: String) {
        sendingImage = false
        sendingProgress = 0
        images.append(dpfPhoto(filename: imageID))
    }
    
    func didReceiveImageIDs(_ images: [String]) {
        for s in images {
            self.images.append(dpfPhoto(filename: s))
        }
        
        print("received all images")
    }
    
    func didCloseConnection() {
        connectionFailed = true
    }
    
    func progressSent(value: Double) {
        self.sendingProgress = value
    }
}

struct ContentView: View {
    @EnvironmentObject var model : Model
    @State var showImagePicker: Bool = false
    @State var image: Image? = nil
    @State var uiimage: UIImage? = nil
    @State var showImageFullView = false
    @State var showActionSheet = false
    
    
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        NavigationView {
            ScrollView {
                
                if(self.model.sendingImage){
                    image?.resizable().frame(width: 100, height: 100)
                        .padding()
                    ProgressView()
                        .padding()
                    ProgressBar()
                        .padding()
                    Divider()
                        .padding()
                }
                
                if self.model.connectionFailed {
                    Text("Couldnt find Photo Frame :(")
                    Button("Retry"){
                        self.model.tryConnect()
                    }
                } else {
                    if model.images.count > 0 {
                        LazyVGrid(columns: columns, spacing: 0) {
                            ForEach(model.images) { i in
                                let address = "\(self.model.dfp.serverAddress)photos/\(i.filename)"
                                AnimatedImage(url: URL(string: address), options: .allowInvalidSSLCertificates)
                                    .onFailure(perform: { (error) in
                                        print("Error fetching image from server:", error)
                                    })
                                    .resizable()
                                    .indicator(.activity)
                                    .frame(width: 100, height: 100)
                                    .clipped()
                                    .onTapGesture {
                                        self.model.selectedImage = i.filename
                                        self.showImageFullView = true
                                        print("tapped on ", i, showImageFullView)
                                        
                                    }
                                    .contextMenu(ContextMenu(menuItems: {
                                        Button(action: {
                                            self.model.delete(image: i.filename)
                                        }, label: {
                                            Text("Delete")
                                            Image(systemName: "trash")
                                        })
                                    }))
                                    
                            }
                        }
                    }
                    else {
                        Text("No images yet")
                    }
                }
                
            }
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $showImageFullView) {
                fullScreenImage(showView: $showImageFullView)
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(sourceType: .photoLibrary) { image in
                    self.uiimage = image
                    self.image = Image(uiImage: image)
                    
                    if(image != nil) {
                        self.model.sendingImage = true
                        model.dfp.send(image: uiimage!)
                    }
                }
            }
            .actionSheet(isPresented: $showActionSheet, content: {
                ActionSheet(title: Text("Settings"), buttons: [.destructive(Text("Forget Photo Frame"), action: {
                    let defaults = UserDefaults.standard
                    defaults.removeObject(forKey: "ipAddress")
                    print("dpf forgotten")
                }),
                .default(Text("Refresh"), action: {
                    self.model.images.removeAll()
                    self.model.dfp.getPhotoIDs()
                }),
                .cancel()])
            })
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        self.showImagePicker.toggle()
                        print("showing image picker", self.showImagePicker)
                    }, label: {
                        Label("Add", systemImage: "plus")
                    })
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        showActionSheet = true
                    }, label: {
                        Label("Add", systemImage: "gearshape")
                    })
                }
            }
        }
    }
}

struct ProgressBar: View {
    @EnvironmentObject var model : Model
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle().frame(width: geometry.size.width , height: geometry.size.height)
                    .opacity(0.3)
                    .foregroundColor(Color(UIColor.systemTeal))
                
                Rectangle().frame(width: min(CGFloat(self.model.sendingProgress)*geometry.size.width, geometry.size.width), height: geometry.size.height)
                    .foregroundColor(Color(UIColor.systemBlue))
                    .animation(.linear)
            }.cornerRadius(45.0)
        }
    }
}

struct fullScreenImage: View {
    @Binding var showView : Bool
    @EnvironmentObject var model : Model
    
    var body : some View {
        VStack {
            GeometryReader { geo in
                let address = "\(self.model.dfp.serverAddress)photos/\(self.model.selectedImage)"
                WebImage(url: URL(string: address), options: .allowInvalidSSLCertificates)
                    .onFailure(perform: { (error) in
                        print("Error fetching image from server:", error)
                    })
                    .resizable()
                    .placeholder(Image(systemName: "photo"))
                    .indicator(.activity)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: geo.size.width)
                    .onTapGesture {
                        showView = false
                    }
            }
            Button("Delete") {
                self.model.delete(image: self.model.selectedImage)
                showView = false
            }
        }
        .onAppear(){
            if self.model.selectedImage.isEmpty {
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

