import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:untitled20/main.dart';

import '../../configs/image_picker_configs.dart';
import '../../models/image_object.dart';
import '../../utils/image_utils.dart';
import '../../utils/log_utils.dart';
import '../common/portrait_mode_mixin.dart';
import '../viewer/image_viewer.dart';
import 'media_album.dart';

/// Picker mode definition: Camera or Album (Photo gallery of device)
class PickerMode {
  /// Camera picker.
  // TODO(rydmike): This const property name does not conform to Dart standards,
  //   but fixing it is a breaking change, thus not changed yet.
  // ignore: constant_identifier_names
  static const int Camera = 0;

  /// Album picker.
  // TODO(rydmike): This const property name does not conform to Dart standards,
  //   but fixing it is a breaking change, thus not changed yet.
  // ignore: constant_identifier_names
  static const int Album = 1;

}


/// Default height of bottom control panel.
const int kBottomControlPanelHeight = 145;

/// Image picker that can use the camera and/or the device photo library.
///
/// It can be used to select **multiple images** from the Android and iOS
/// image library. It can also **take multiple new pictures with the camera**,
/// and allow the user to **edit** them before using them. Edits include
/// rotation, cropping, and adding sticker as well as filters.
class ImagePicker extends StatefulWidget {
  /// Default constructor for the photo and media image picker.
  const ImagePicker(
      {final Key? key,
      this.maxCount = 10,
      this.isFullscreenImage = false,
      this.isCaptureFirst = true,
        this.mode=PickerMode.Album,
      this.configs})
      : super(key: key);

  /// Max selecting count
  final int maxCount;

  final int mode;

  final CameraLensDirection initialDirection = CameraLensDirection.back;

  /// Default for capturing new image in fullscreen mode or preview mode
  final bool isFullscreenImage;

  /// Custom configuration, if not provided, plugin will use
  /// default configuration.
  final ImagePickerConfigs? configs;

  /// Default mode for selecting image: capture new image or select
  /// image from album.
  final bool isCaptureFirst;


  @override
  _ImagePickerState createState() => _ImagePickerState();
}

class _ImagePickerState extends State<ImagePicker>
    with
        // ignore: prefer_mixin
        WidgetsBindingObserver,
        TickerProviderStateMixin,
        PortraitStatefulModeMixin<ImagePicker> {
  /// List of camera detected in device


  /// Default mode for selecting images.
  int _mode=0;
  /// Camera controller
  CameraController? _controller;

  CameraController? _controller2;

  /// Scroll controller for selecting images screen.
  final _scrollController = ScrollController();

  /// Future object for initializing camera controller.
  Future<void>? _initializeControllerFuture;

  /// Selecting images
  List<ImageObject> _selectedImages = [];

  /// Flag indicating current used flashMode.
  FlashMode _flashMode = FlashMode.auto;

  /// Flag indicating state of camera, which capturing or not.
  bool _isCapturing = false;

  bool detect=false;

  /// Flag indicating state of plugin, which creating output or not.
  bool _isOutputCreating = false;

  /// Current camera preview mode.
  bool _isFullscreenImage = false;

  /// Flag indicating state of image selecting.
  bool _isImageSelectedDone = false;

  /// Flag indicating status of permission to access cameras
  bool _isCameraPermissionOK = false;

  /// Flag indicating status of permission to access photo libray
  bool _isGalleryPermissionOK = false;

  /// Image configuration.
  ImagePickerConfigs _configs = ImagePickerConfigs();

  /// Photo album list.
  List<AssetPathEntity> _albums = [];

  /// Currently viewing album.
  AssetPathEntity? _currentAlbum;

  /// Album thumbnail cache.
  List<Uint8List?> _albumThumbnails = [];

  /// Key for current album object.
  final GlobalKey<MediaAlbumState> _currentAlbumKey = GlobalKey();

  /// Min available zoom ratio.
  double _minAvailableZoom = 1;

  /// Max available zoom ratio.
  double _maxAvailableZoom = 1;

  /// Current scale ratio.
  double _currentScale = 1;

  /// Base scale ratio.
  double _baseScale = 1;

  /// Counting pointers (number of user fingers on screen).
  int _pointers = 0;

  /// Min available exposure offset.
  double _minAvailableExposureOffset = 0;

  /// Max available exposure offset.
  double _maxAvailableExposureOffset = 0;

  /// Current exposure offset.
  double _currentExposureOffset = 0;

  /// Exposure mode control controller.
  late AnimationController _exposureModeControlRowAnimationController;

  /// Exposure mode control.
  late Animation<double> _exposureModeControlRowAnimation;

  /// Global key for this screen.
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();


  bool _isDisposed = false;

  bool _canProcess=true;
  
  bool _isBusy=false;
  
  bool _changingCameraLens=false;

  double zoomLevel=0.0,minZoomLevel=0.0,maxZoomLevel=0.0;
  
  CustomPaint? _customPaint;

  int _cameraIndex=0;
  
  String? _text;


  final FaceDetector _faceDetector=FaceDetector(options:FaceDetectorOptions(
      enableContours: true,
      enableClassification: true
  ));
  
  @override
  void initState() {
    _mode =widget.mode;
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    

    // Setting preview screen mode from configuration
    if (widget.configs != null) _configs = widget.configs!;
    _flashMode = _configs.flashMode;
    _isFullscreenImage = widget.isFullscreenImage;
    ///_mode = (widget.isCaptureFirst && _configs.cameraPickerModeEnabled)
        ///? PickerMode.Camera
        ///: PickerMode.Album;

    // Setting animation controller
    _exposureModeControlRowAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _exposureModeControlRowAnimation = CurvedAnimation(
      parent: _exposureModeControlRowAnimationController,
      curve: Curves.easeInCubic,
    );

    // Init camera or album
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_mode == PickerMode.Camera) {
        _startLive();

      } else {
        await _initPhotoGallery();
      }
    });

  }

  void _switchScreenMode(){
    if(_mode==PickerMode.Camera){
      _controller2?.stopImageStream();
    }
    else{
      _startLive();
    }
    setState(() {

    });
  }

  Future _startLive() async{
    detect=true;
    final camera=cameras[_cameraIndex];
    _controller2=CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false
    );
    _controller2?.initialize().then((_){
      if(!mounted){
        return;
      }
      _controller2?.getMaxZoomLevel().then((value){
        maxZoomLevel=value;
      });
      _controller2?.getMinZoomLevel().then((value){
        zoomLevel=value;
        minZoomLevel=value;
      });
      print("startlive");
      print(_controller2);

      _isCameraPermissionOK = true;



      _initCameraController();

      setState(() {


      });



    });
  }

  Future _stopLive() async{
    await _controller2?.stopImageStream();
    await _controller2?.dispose();
  }

  Future _switcherCamera()async{
    setState(() =>_changingCameraLens=true);
    _cameraIndex=(_cameraIndex+1)%cameras.length;
    await _controller2?.stopImageStream();
    await _startLive();
    setState(()=>_changingCameraLens=false);
  }

  Future _processCameraImage(final CameraImage image)async{
    print(image);
    final WriteBuffer allBytes=WriteBuffer();
    for(final Plane plane in image.planes){
      allBytes.putUint8List(plane.bytes);
    }
    final bytes=allBytes.done().buffer.asUint8List();
    final Size imageSize=Size(image.width.toDouble(),image.height.toDouble(),);
    final camera=cameras[_cameraIndex];
    final imageRotation=
        InputImageRotationValue.fromRawValue(camera.sensorOrientation) ??
            InputImageRotation.rotation0deg;
    final inputImageFormat=
        InputImageFormatValue.fromRawValue(image.format.raw) ??
            InputImageFormat.nv21;

    final planeData=image.planes.map((final Plane plane){
      return InputImagePlaneMetadata(bytesPerRow: plane.bytesPerRow,height: plane.height,width: plane.width);

    }).toList();
    final inputImageData=InputImageData(
        size: imageSize,
        imageRotation: imageRotation,
        inputImageFormat: inputImageFormat,
        planeData: planeData);
    final inputImage=InputImage.fromBytes(bytes: bytes, inputImageData: inputImageData);
    print("in2");
    print(inputImage);
    processImage(inputImage);

  }

  Future<void>processImage(final InputImage inputImage)async{
    if(!_canProcess)return;
    if(_isBusy)return;
    _isBusy=true;
    setState(() {
    });
    final faces=await _faceDetector.processImage(inputImage);
    print(faces);
    if(inputImage.inputImageData?.size!=null&&
        inputImage.inputImageData?.imageRotation!=null){
      final painter=FaceDetectorPainter(
          faces, inputImage.inputImageData!.size,
          inputImage.inputImageData!.imageRotation);
      _customPaint=CustomPaint(painter: painter,);
    }else{
      String text='${faces.length}';
      for(final face in faces){
        text+='face: ${face.boundingBox}\n\n';
      }
      _text=text;
      _customPaint=null;
    }
    _isBusy=false;
    print(faces);
    if(mounted){
      setState(() {

      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _exposureModeControlRowAnimationController.dispose();
    _controller2?.dispose();
    _controller2 = null;
    cameras.clear();
    _albums.clear();
    _albumThumbnails.clear();
    _canProcess=false;
    _faceDetector.close();
    super.dispose();
  }

  /// Called when the system puts the app in the background or
  /// returns the app to the foreground.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _controller2;

    // App state changed before we got the chance to initialize.
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    // Process when app state changed
    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
      _isDisposed = true;
    } else if (state == AppLifecycleState.resumed) {
      _isDisposed = false;
      _onNewCameraSelected(cameraController.description);
    }
  }

  /// Initialize the camera for photo capturing
  Future<void> _initPhotoCapture() async {
    LogUtils.log("[_initPhotoCapture] start");

    try {
      // List all cameras in current device.

      // Select new camera for capturing.
      if (cameras.isNotEmpty) {
        final CameraDescription? newDescription = _getCamera(
            cameras, _getCameraDirection(_configs.cameraLensDirection));
        if (newDescription != null) {
          await _onNewCameraSelected(newDescription);
        }
      }
    } on CameraException catch (e) {
      LogUtils.log('Camera error ${e.code}, ${e.description}');
    }



  }

  /// Get camera direction.
  CameraLensDirection? _getCameraDirection(int? direction) {
    if (direction == null) {
      return null;
    } else if (direction == 0) {
      return CameraLensDirection.front;
    } else {
      return CameraLensDirection.back;
    }
  }

  /// Get camera description.
  CameraDescription? _getCamera(
      List<CameraDescription> cameras, CameraLensDirection? direction) {
    if (direction == null) {
      return cameras.first;
    } else {
      final CameraDescription newDescription = cameras.firstWhere(
          (description) => description.lensDirection == direction,
          orElse: () => cameras.first);
      return newDescription;
    }
  }

  /// Initialize current selected camera
  void _initCameraController() {
    // Create future object for initializing new camera controller.
    final cameraController = _controller2!;
    _initializeControllerFuture =
        cameraController.initialize().then((value) async {
      LogUtils.log("[_onNewCameraSelected] cameraController initialized.");

      _isCameraPermissionOK = true;

      // After initialized, setting zoom & exposure values
      await Future.wait([
        cameraController.lockCaptureOrientation(DeviceOrientation.portraitUp),
        cameraController.setFlashMode(_configs.flashMode),
        cameraController
            .getMinExposureOffset()
            .then((value) => _minAvailableExposureOffset = value),
        cameraController
            .getMaxExposureOffset()
            .then((value) => _maxAvailableExposureOffset = value),
        cameraController
            .getMaxZoomLevel()
            .then((value) => _maxAvailableZoom = value),
        cameraController
            .getMinZoomLevel()
            .then((value) => _minAvailableZoom = value),
      ]);


      if(detect){
        print("dont!");
                _controller2?.startImageStream(_processCameraImage);}
        else{
          print("chap");
          await _controller2?.stopImageStream();
          if (!(_controller2?.value.isTakingPicture ?? true)) {
            try {
              // Scroll to end of list.

              // Take new picture.
              final file = await _controller2!.takePicture();
              print(file);
              LogUtils.log(
                  "[_buildCameraControls] takePicture done");

              Map<String, dynamic>? croppingParams;
              if (!_isFullscreenImage) {
                croppingParams = <String, dynamic>{};
                if (mounted) {
                  final size = MediaQuery.of(context).size;
                  croppingParams["originX"] = 0;
                  croppingParams["originY"] = 0;
                  croppingParams["widthPercent"] = 1.0;
                  if (_configs.cameraPickerModeEnabled &&
                      _configs.albumPickerModeEnabled) {
                    croppingParams["heightPercent"] =
                        (size.height -
                            kBottomControlPanelHeight) /
                            size.height;
                  } else {
                    croppingParams["heightPercent"] =
                        (size.height -
                            kBottomControlPanelHeight +
                            32) /
                            size.height;
                  }
                }
              }
              final capturedFile = await _imagePreProcessing(
                  file.path,
                  croppingParams: croppingParams);

              setState(() {
                LogUtils.log(
                    "[_buildCameraControls] update image "
                        "list after capturing");
                _selectedImages.add(ImageObject(
                    originalPath: capturedFile.path,
                    modifiedPath: capturedFile.path));
              });
            } on CameraException catch (e) {
              LogUtils.log('${e.description}');
            }
          }
          _controller2?.startImageStream(_processCameraImage);

      }





      // Refresh screen for applying new updated
      if (mounted && detect) {

        setState(() {
          print("hey");
        });
      }
    }).catchError((e) {
      LogUtils.log('Camera error ${e.toString()}');
    });
  }

  /// Select new camera for capturing
  Future<void> _onNewCameraSelected(CameraDescription cameraDescription) async {
    LogUtils.log("[_onNewCameraSelected] start");

    // Dispose old then create new camera controller
    if (_controller2 != null) {
      await _controller2!.dispose();
    }
    final CameraController cameraController = CameraController(
      cameraDescription,
      _configs.resolutionPreset,
      enableAudio: false,
    );
    _controller2 = cameraController;

    print(_controller2);

    // Init selected camera
    _initCameraController();



    // If the controller is updated then update the UI.
    _controller2!.addListener(() {
      if (mounted) setState(() {});
      if (cameraController.value.hasError) {
        LogUtils.log('Camera error ${cameraController.value.errorDescription}');
      }
    });


  }

  /// Init photo gallery for image selecting
  Future<void> _initPhotoGallery() async {
    LogUtils.log("[_initPhotoGallery] start");

    try {
      // Request permission for image selecting
      final result = await PhotoManager.requestPermissionExtend();
      if (result.isAuth) {
        LogUtils.log('PhotoGallery permission allowed');

        _isGalleryPermissionOK = true;

        // Get albums then set first album as current album
        _albums = await PhotoManager.getAssetPathList(type: RequestType.image);
        if (_albums.isNotEmpty) {
          final isAllAlbum = _albums.firstWhere((element) => element.isAll,
              orElse: () => _albums.first);
          setState(() {
            _currentAlbum = isAllAlbum;
          });
        }
      } else {
        LogUtils.log('PhotoGallery permission not allowed');
      }
    } catch (e) {
      LogUtils.log('PhotoGallery error ${e.toString()}');
    }
  }

  /// Run pre-processing for input image in [path] and [croppingParams]
  Future<File> _imagePreProcessing(String path, {Map? croppingParams}) async {
    LogUtils.log("[_imagePreProcessing] start");

    if (_configs.imagePreProcessingEnabled) {
      // Run compress & resize image
      var file = await ImageUtils.compressResizeImage(path,
          maxWidth: _configs.maxWidth,
          maxHeight: _configs.maxHeight,
          quality: _configs.compressQuality);
      if (croppingParams != null) {
        file = await ImageUtils.cropImage(file.path,
            originX: croppingParams["originX"] as int,
            originY: croppingParams["originY"] as int,
            widthPercent: croppingParams["widthPercent"] as double,
            heightPercent: croppingParams["heightPercent"] as double);
      }

      LogUtils.log("[_imagePreProcessing] end");
      return file;
    }

    LogUtils.log("[_imagePreProcessing] end");
    return File(path);
  }

  /// Run post-processing for output image
  Future<File> _imagePostProcessing(String path) async {
    LogUtils.log("[_imagePostProcessing] start");

    if (!_configs.imagePreProcessingEnabled) {
      LogUtils.log("[_imagePostProcessing] end");
      return ImageUtils.compressResizeImage(path,
          maxWidth: _configs.maxWidth,
          maxHeight: _configs.maxHeight,
          quality: _configs.compressQuality);
    }

    LogUtils.log("[_imagePostProcessing] end");
    return File(path);
  }

  /// Show confirmation dialog when exit without saving selected images
  Future<bool> _onWillPop() async {
    if (!_configs.showNonSelectedAlert ||
        _isImageSelectedDone ||
        _selectedImages.isEmpty) return true;

    return (await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
                  title: Text(_configs.textConfirm),
                  content: Text(_configs.textConfirmExitWithoutSelectingImages),
                  actions: <Widget>[
                    TextButton(
                      style: TextButton.styleFrom(
                        primary: Colors.black87,
                        minimumSize: const Size(88, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.all(Radius.circular(2)),
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text(_configs.textNo),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        primary: Colors.black87,
                        minimumSize: const Size(88, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.all(Radius.circular(2)),
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(true),
                      child: Text(_configs.textYes),
                    ),
                  ],
                ))) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Use theme based AppBar colors if config values are not defined.
    // The logic is based on same approach that is used in AppBar SDK source.
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final AppBarTheme appBarTheme = AppBarTheme.of(context);
    final Color _appBarBackgroundColor = Colors.white;
        appBarTheme.backgroundColor ??
        (colorScheme.brightness == Brightness.dark
            ? colorScheme.surface
            : colorScheme.primary);
    final Color _appBarTextColor = _configs.appBarTextColor ??
        appBarTheme.foregroundColor ??
        (colorScheme.brightness == Brightness.dark
            ? colorScheme.onSurface
            : colorScheme.onPrimary);
    final Color _appBarDoneButtonColor =
        _configs.appBarDoneButtonColor ?? _appBarBackgroundColor;

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
          key: _scaffoldKey,
          backgroundColor: _configs.backgroundColor,
          appBar: AppBar(
            leading: IconButton(
              onPressed: (){
                Navigator.push(
                    context,
                    MaterialPageRoute(builder:(context)=>MyHomePage(isSelected: [true],)));
              },
              icon: Icon(Icons.arrow_back,color:Colors.greenAccent,),
            ),
            title: _buildAppBarTitle(
              context,
              _appBarBackgroundColor,
              _appBarTextColor,
            ),
            backgroundColor: _appBarBackgroundColor,
            foregroundColor: _appBarTextColor,
            centerTitle: false,
            actions: <Widget>[
            ],
          ),
          body: SafeArea(child: _buildBodyView(context))),
    );
  }

  /// Build app bar title
  Widget _buildAppBarTitle(
    BuildContext context,
    Color appBarBackgroundColor,
    Color appBarTextColor,
  ) {
    return GestureDetector(
        onTap: (_mode == PickerMode.Album)
            ? () {
                Navigator.of(context, rootNavigator: true)
                    .push<void>(PageRouteBuilder(
                        pageBuilder: (context, animation, __) {
                          return Scaffold(
                              appBar: AppBar(
                                  title: _buildAlbumSelectButton(context,
                                      isPop: true),
                                  backgroundColor: appBarBackgroundColor,
                                  foregroundColor: appBarTextColor,
                                  centerTitle: false),
                              body: Material(
                                  color: Colors.white,
                                  child: SafeArea(
                                    child: _buildAlbumList(_albums, context,
                                        (val) {
                                      Navigator.of(context).pop();
                                      setState(() {
                                        _currentAlbum = val;
                                      });
                                      _currentAlbumKey.currentState
                                          ?.updateStateFromExternal(
                                              album: _currentAlbum);
                                    }),
                                  )));
                        },
                        fullscreenDialog: true));
              }
            : null,
        child: _buildAlbumSelectButton(context,
            isCameraMode: _mode == PickerMode.Camera));
  }

  /// Function used to select the images and close the image picker.
  Future<void> _doneButtonPressed() async {
    setState(() {
      _isOutputCreating = true;
    });
    // Compress selected images then return.
    for (final f in _selectedImages) {
      // Run image post processing
      f.modifiedPath = (await _imagePostProcessing(f.modifiedPath)).path;

      // Run label detector
      if (_configs.labelDetectFunc != null && f.recognitions == null) {
        f.recognitions = await _configs.labelDetectFunc!(f.modifiedPath);
        if (f.recognitions?.isNotEmpty ?? false) {
          f.label = f.recognitions!.first.label;
        } else {
          f.label = "";
        }
        LogUtils.log("f.recognitions: ${f.recognitions}");
      }
    }
    _isImageSelectedDone = true;
    if (!mounted) return;
    Navigator.push(
        context,
        MaterialPageRoute(builder:(context)=>MyHomePage(isSelected: [true],)));
  }

  // TODO(rydmike): The image picker uses a lot of Widget build functions.
  //   This may sometimes be inefficient and even an anti-pattern in Flutter.
  //   It is not always a bad thing though. Still we should review it later
  //   and see if there are critical ones that it would be better to replace
  //   with StatelessWidgets or StatefulWidgets.

  /// Build done button.


  /// Build body view.
  Widget _buildBodyView(BuildContext context) {
    LogUtils.log("[_buildBodyView] start");

    final size = MediaQuery.of(context).size;
    final bottomHeight = (widget.maxCount == 1)
        ? (kBottomControlPanelHeight - 40)
        : kBottomControlPanelHeight;

    return Stack(children: [
      SizedBox(height: size.height, width: size.width),
      if (_mode == PickerMode.Camera)
        _isCameraPermissionOK
            ? Stack(
            children :[
              Center(child: _buildCameraPreview(context)),

            ]
        )
            : _buildCameraRequestPermissionView(context)
      else
        _isGalleryPermissionOK
            ? _buildAlbumPreview(context)
            : _builGalleryRequestPermissionView(context),
      if(_customPaint!=null)_customPaint!,

      if (_mode == PickerMode.Camera) ...[
        Positioned(
            bottom: 170,
            left: 5,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _exposureModeControlRowWidget(),
              _buildExposureButton(context),
            ])),
        Positioned(
            bottom: 170,
            left: 0,
            right: 0,
            child: Center(child: _buildZoomRatioButton(context))),
      ],
      Positioned(
          bottom: 0, left: 0, right: 0, child: _buildBottomPanel(context))
    ]);
  }

  /// Build zoom ratio button.
  Widget _buildZoomRatioButton(BuildContext context) {
    return TextButton(
        style: TextButton.styleFrom(
          primary: Colors.black12,
          minimumSize: const Size(88, 36),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: const CircleBorder(),
        ),
        onPressed: null,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Text("${_currentScale.toStringAsFixed(1)}x",
                style: const TextStyle(color: Colors.white)),
          ),
        ));
  }

  /// Build exposure adjusting button.
  Widget _buildExposureButton(BuildContext context) {
    return TextButton(
      style: TextButton.styleFrom(
        primary: Colors.black12,
        minimumSize: const Size(88, 36),
        padding: const EdgeInsets.all(4),
        shape: const CircleBorder(),
      ),
      onPressed: _controller2 != null ? _onExposureModeButtonPressed : null,
      child: const Icon(Icons.exposure_outlined, color: Colors.white, size: 40),
    );
  }

  /// Exposure change mode button event.
  void _onExposureModeButtonPressed() {
    if (_exposureModeControlRowAnimationController.value == 1) {
      _exposureModeControlRowAnimationController.reverse();
    } else {
      _exposureModeControlRowAnimationController.forward();
    }
  }


  /// Build bottom panel.
  Widget _buildBottomPanel(BuildContext context) {
    // Add leading text and colon+blank, only if 'textSelectedImagesTitle' is
    // not blank in a none breaking way to previous version.
    return Container(
      color: ((_mode == PickerMode.Camera) && _isFullscreenImage)
          ? _configs.bottomPanelColorInFullscreen
          : _configs.bottomPanelColor,
      padding: const EdgeInsets.all(8),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _buildCameraControls(context),
        Padding(
            padding: const EdgeInsets.all(8),
            child: _buildPickerModeList(context))
      ]),
    );
  }

  /// Build album select button.
  Widget _buildAlbumSelectButton(BuildContext context,
      {bool isPop = false, bool isCameraMode = false}) {
    if (isCameraMode) {
      return Text(" ",
          style: TextStyle(color: _configs.appBarTextColor, fontSize: 16));
    }

    final size = MediaQuery.of(context).size;
    final container = Container(
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              constraints: BoxConstraints(maxWidth: size.width / 2.5),
              child: Text(_currentAlbum?.name ?? "",
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(color: Colors.greenAccent, fontSize: 16)),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(
                  isPop
                      ? Icons.arrow_upward_outlined
                      : Icons.arrow_downward_outlined,
                  size: 16,color: Colors.greenAccent,),
            )
          ],
        ));

    return isPop
        ? GestureDetector(
            child: container,
            onTap: () async {
              Navigator.of(context).pop();
            },
          )
        : container;
  }

  /// Build camera request permission view
  Widget _buildCameraRequestPermissionView(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bottomHeight = (widget.maxCount == 1)
        ? (kBottomControlPanelHeight - 40)
        : kBottomControlPanelHeight;
    return SizedBox(
      width: size.width,
      height: size.height - bottomHeight,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextButton(
            style: TextButton.styleFrom(
              backgroundColor: Colors.grey.shade400,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(30)),
              ),
            ),
            onPressed: _initCameraController,
            child: Text(_configs.textRequestPermission,
                style: const TextStyle(color: Colors.black)),
          ),
          Text(_configs.textRequestCameraPermission,
              style: const TextStyle(color: Colors.grey))
        ],
      ),
    );
  }

  /// Build camera preview widget.
  Widget _buildCameraPreview(BuildContext context) {
    LogUtils.log("[_buildCameraPreview] start");

    print("ㅈㅂ");
    print(_controller2?.value);
    print(_isDisposed);

    final size = MediaQuery.of(context).size;
    if (_controller2?.value == null || _isDisposed) {
      return SizedBox(
          width: size.width,
          height: size.height,
          child: const Center(child: CircularProgressIndicator()));
    }

    return FutureBuilder<void>(
        key: const ValueKey(-1),
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return (_controller2?.value.isInitialized ?? false)
                ? SizedBox(
                    width: size.width,
                    height: size.height,
                    child: AspectRatio(
                        aspectRatio: _controller2!.value.aspectRatio,
                        child: Listener(
                            onPointerDown: (_) => _pointers++,
                            onPointerUp: (_) => _pointers--,
                            child: CameraPreview(_controller2!, child:
                                LayoutBuilder(builder: (BuildContext context,
                                    BoxConstraints constraints) {
                              return GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onScaleStart: _handleScaleStart,
                                onScaleUpdate: _handleScaleUpdate,
                                onTapDown: (details) =>
                                    _onViewFinderTap(details, constraints),
                              );
                            })))))
                : Container();
          }
          return const Center(child: CircularProgressIndicator());
        });
  }

  /// Tap event on camera preview.
  void _onViewFinderTap(TapDownDetails details, BoxConstraints constraints) {
    if (_controller2 == null) {
      return;
    }

    final CameraController cameraController = _controller2!;

    final offset = Offset(
      details.localPosition.dx / constraints.maxWidth,
      details.localPosition.dy / constraints.maxHeight,
    );
    cameraController.setExposurePoint(offset);
    cameraController.setFocusPoint(offset);
  }

  /// Handle scale start event.
  void _handleScaleStart(ScaleStartDetails details) {
    _baseScale = _currentScale;
  }

  /// Handle scale updated event.
  Future<void> _handleScaleUpdate(ScaleUpdateDetails details) async {
    // When there are not exactly two fingers on screen don't scale.
    if (_controller2 == null || _pointers != 2) {
      return;
    }

    final double scale = (_baseScale * details.scale)
        .clamp(_minAvailableZoom, _maxAvailableZoom);

    await _controller2!.setZoomLevel(scale);
    await _controller2!.setZoomLevel(scale);

    setState(() {
      _currentScale = scale;
    });
  }

  /// Build camera request permission view
  Widget _builGalleryRequestPermissionView(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bottomHeight = (widget.maxCount == 1)
        ? (kBottomControlPanelHeight - 40)
        : kBottomControlPanelHeight;
    return SizedBox(
        width: size.width,
        height: size.height - bottomHeight,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          TextButton(
            style: TextButton.styleFrom(
              backgroundColor: Colors.grey.shade400,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(30)),
              ),
            ),
            onPressed: _initPhotoGallery,
            child: Text(_configs.textRequestPermission,
                style: const TextStyle(color: Colors.black)),
          ),
          Text(_configs.textRequestGalleryPermission,
              style: const TextStyle(color: Colors.grey))
        ]));
  }

  /// Build album preview widget.
  Widget _buildAlbumPreview(BuildContext context) {
    LogUtils.log("[_buildAlbumPreview] start");

    final bottomHeight = (widget.maxCount == 1)
        ? (kBottomControlPanelHeight - 40)
        : kBottomControlPanelHeight;

    return SizedBox(
      height: MediaQuery.of(context).size.height - bottomHeight,
      child: _currentAlbum != null
          ? MediaAlbum(
              key: _currentAlbumKey,
              gridCount: _configs.albumGridCount,
              maxCount: 10000,
              album: _currentAlbum!,
              selectedImages: _selectedImages,
              preProcessing: _imagePreProcessing,
              onImageSelected: (image) async {
                LogUtils.log("[_buildAlbumPreview] onImageSelected start");

                final idx = _selectedImages
                    .indexWhere((element) => element.assetId == image.assetId);
              })
          : const SizedBox(),
    );
  }

  /// Build album thumbnail preview.
  Future<List<Uint8List?>> _buildAlbumThumbnails() async {
    LogUtils.log("[_buildAlbumThumbnails] start");

    if (_albums.isNotEmpty && _albumThumbnails.isEmpty) {
      final List<Uint8List?> ret = [];
      for (final a in _albums) {
        final f = await (await a.getAssetListRange(start: 0, end: 1))
            .first
            .thumbnailDataWithSize(ThumbnailSize(
                _configs.albumThumbWidth, _configs.albumThumbHeight));
        ret.add(f);
      }
      _albumThumbnails = ret;
    }

    return _albumThumbnails;
  }

  /// Build album list screen.
  Widget _buildAlbumList(List<AssetPathEntity> albums, BuildContext context,
      Function(AssetPathEntity newValue) callback) {
    LogUtils.log("[_buildAlbumList] start");

    return FutureBuilder(
      future: _buildAlbumThumbnails(),
      builder: (BuildContext context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          return ListView.builder(
              itemCount: _albums.length,
              itemBuilder: (context, i) {
                final album = _albums[i];
                final thumbnail = _albumThumbnails[i]!;
                return InkWell(
                  child: ListTile(
                      leading: SizedBox(
                          width: 80,
                          height: 80,
                          child: Image.memory(thumbnail, fit: BoxFit.cover)),
                      title: Text(album.name,
                          style: const TextStyle(color: Colors.black)),
                      subtitle: Text(album.assetCount.toString(),
                          style: const TextStyle(color: Colors.grey)),
                      onTap: () async {
                        callback.call(album);
                      }),
                );
              });
        } else {
          return const Center(
            child: CupertinoActivityIndicator(),
          );
        }
      },
    );
  }

  /// Reorder selected image list event.
  bool? _reorderSelectedImageList(int oldIndex, int newIndex) {
    LogUtils.log("[_reorderSelectedImageList] start");

    if (oldIndex >= _selectedImages.length ||
        newIndex > _selectedImages.length ||
        oldIndex < 0 ||
        newIndex < 0) return false;

    int _newIndex = newIndex;
    setState(() {
      if (_newIndex > oldIndex) {
        _newIndex -= 1;
      }
      final items = _selectedImages.removeAt(oldIndex);
      _selectedImages.insert(_newIndex, items);
      return;
    });
  }

  /// Build reorderable selected image list.
  Widget _buildReorderableSelectedImageList(BuildContext context) {
    LogUtils.log("[_buildReorderableSelectedImageList] start");

    Widget makeThumbnailImage(String? path) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.file(
          File(path!),
          fit: BoxFit.cover,
          width: _configs.thumbWidth.toDouble(),
          height: _configs.thumbHeight.toDouble(),
        ),
      );
    }

    /// Remove image in the list at index.
    void _removeImage(final int index) {
      setState(() {
        _selectedImages.removeAt(index);
      });
      _currentAlbumKey.currentState
          ?.updateStateFromExternal(selectedImages: _selectedImages);
    }

    /// Make an image thumbnail widget.
    Widget makeThumbnailWidget(String? path, int index) {
      if (!_configs.showDeleteButtonOnSelectedList) {
        return makeThumbnailImage(path);
      }
      return Stack(fit: StackFit.passthrough, children: [
        makeThumbnailImage(path),
        Positioned(
          top: 2,
          right: 2,
          child: GestureDetector(
              child: Container(
                margin: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.greenAccent,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                height: 24,
                width: 24,
                child: const Icon(
                  Icons.close,
                  size: 16,
                  color: Colors.greenAccent,
                ),
              ),
              onTap: () {
                if (_configs.showRemoveImageAlert) {
                  showDialog<void>(
                    context: context,
                    builder: (BuildContext context) {
                      // return object of type Dialog
                      return AlertDialog(
                        title: Text(_configs.textConfirm),
                        content: Text(_configs.textConfirmDelete),
                        actions: <Widget>[
                          TextButton(
                            child: Text(_configs.textNo),
                            onPressed: () {
                              Navigator.of(context).pop();
                            },
                          ),
                          TextButton(
                            child: Text(_configs.textYes),
                            onPressed: () {
                              Navigator.of(context).pop();
                              _removeImage(index);
                            },
                          ),
                        ],
                      );
                    },
                  );
                } else {
                  _removeImage(index);
                }
              }),
        )
      ]);
    }

    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        height: (_configs.thumbHeight + 8).toDouble(),
    );
  }

  /// Return used IconData for corresponding FlashMode.
  ///
  /// [FlashMode.torch], is treated a always using the flash in this app.
  IconData _flashModeIcon(final FlashMode flashMode) {
    switch (flashMode) {
      case FlashMode.auto:
        return Icons.flash_auto_outlined;
      case FlashMode.off:
        return Icons.flash_off_outlined;
      case FlashMode.torch:
      case FlashMode.always:
        return Icons.flash_on_outlined;
    }
  }

  /// Cycle through FlashMode, called when users taps on FlashMode.
  ///
  /// This function just updates the local state _flashMode variable, but does
  /// not call setState, it is upp to caller to set state when needed.
  ///
  /// [FlashMode.torch], is treated a always using the flash in this app.
  void _cycleFlashMode() {
    switch (_flashMode) {
      case FlashMode.auto:
        _flashMode = FlashMode.off;
        break;
      case FlashMode.off:
        _flashMode = FlashMode.always;
        break;
      case FlashMode.torch:
      case FlashMode.always:
        _flashMode = FlashMode.auto;
    }
  }

  /// Build camera controls such as change flash mode, switch cameras,
  /// capture button, etc.
  Widget _buildCameraControls(BuildContext context) {
    final isMaxCount = _selectedImages.length >= widget.maxCount;

    final canSwitchCamera =
        cameras.length > 1 && _configs.cameraLensDirection == null;

    return _mode == PickerMode.Camera
        ? Container(
            height: 135,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_configs.showFlashMode)
                    GestureDetector(
                      child: Icon(_flashModeIcon(_flashMode),
                          size: 32, color: Colors.white),
                      onTap: () async {
                        // Ensure that the camera is initialized.
                        await _initializeControllerFuture;
                        // Cycle to next flash mode.
                        _cycleFlashMode();
                        // Update camera to new flash mode.
                        await _controller2!
                            .setFlashMode(_flashMode)
                            .then((value) => setState(() {}));
                      },
                    )
                  else
                    // We use a transparent icon with no tap, to make
                    // it take up same space as when it is there, to ensure
                    // identical layout as when it is shown.
                    Icon(_flashModeIcon(_flashMode),
                        size: 32, color: Colors.transparent),
                  GestureDetector(
                    onTapDown: !isMaxCount
                        ? (td) {
                            setState(() {
                              _isCapturing = true;
                            });
                          }
                        : null,
                    onTapUp: !isMaxCount
                        ? (td) {
                            setState(() {
                              _isCapturing = false;
                            });
                          }
                        : null,

                    onTap: (!(_controller2?.value.isTakingPicture ?? true))
                        ? () async {
                            LogUtils.log(
                                "[_buildCameraControls] capture pressed");
                            detect=false;

                            // Ensure that the camera is initialized.
                            _initCameraController();

                            if (!(_controller2?.value.isTakingPicture ?? true)) {
                              try {
                                // Scroll to end of list.

                                // Take new picture.
                                final file = await _controller2!.takePicture();
                                print(file);
                                LogUtils.log(
                                    "[_buildCameraControls] takePicture done");

                                Map<String, dynamic>? croppingParams;
                                if (!_isFullscreenImage) {
                                  croppingParams = <String, dynamic>{};
                                  if (mounted) {
                                    final size = MediaQuery.of(context).size;
                                    croppingParams["originX"] = 0;
                                    croppingParams["originY"] = 0;
                                    croppingParams["widthPercent"] = 1.0;
                                    if (_configs.cameraPickerModeEnabled &&
                                        _configs.albumPickerModeEnabled) {
                                      croppingParams["heightPercent"] =
                                          (size.height -
                                                  kBottomControlPanelHeight) /
                                              size.height;
                                    } else {
                                      croppingParams["heightPercent"] =
                                          (size.height -
                                                  kBottomControlPanelHeight +
                                                  32) /
                                              size.height;
                                    }
                                  }
                                }
                                final capturedFile = await _imagePreProcessing(
                                    file.path,
                                    croppingParams: croppingParams);

                                setState(() {
                                  LogUtils.log(
                                      "[_buildCameraControls] update image "
                                      "list after capturing");
                                  _selectedImages.add(ImageObject(
                                      originalPath: capturedFile.path,
                                      modifiedPath: capturedFile.path));
                                });
                              } on CameraException catch (e) {
                                LogUtils.log('${e.description}');
                              }
                            }
                          }
                        : null,
                    child: Icon(Icons.adjust_rounded,
                        size: (100 + (_isCapturing ? (0) : 0)).toDouble(),
                        color: _isCapturing ? Colors.green : Colors.greenAccent),
                  ),
                  GestureDetector(
                    onTap: canSwitchCamera && _configs.showLensDirection
                        ? () async {
                            final lensDirection =
                                _controller2!.description.lensDirection;
                            final CameraDescription? newDescription =
                                _getCamera(
                                    cameras,
                                    lensDirection == CameraLensDirection.front
                                        ? CameraLensDirection.back
                                        : CameraLensDirection.front);
                            print("switcher");
                            if (newDescription != null) {
                              LogUtils.log("Start new camera: "
                                  "${newDescription.toString()}");
                              await _onNewCameraSelected(newDescription);
                            }
                          }
                        : null,
                    child: Icon(Icons.switch_camera_outlined,
                        size: 32,
                        color: _configs.showLensDirection
                            ? (canSwitchCamera ? Colors.white : Colors.grey)
                            : Colors.transparent),
                  )
                ]),
          )
        : const SizedBox();
  }

  /// Build picker mode list.
  Widget _buildPickerModeList(BuildContext context) {
    if (_configs.albumPickerModeEnabled && _configs.cameraPickerModeEnabled) {
      return CupertinoSlidingSegmentedControl(
          backgroundColor: Colors.transparent,
          thumbColor: Colors.transparent,
          children: {
            0: Text(_configs.textCameraTitle,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: (_mode == PickerMode.Camera)
                        ? Colors.greenAccent
                        : Colors.grey)),
            1: Text(_configs.textAlbumTitle,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: (_mode == PickerMode.Album)
                        ? Colors.greenAccent
                        : Colors.grey)),
          },
          groupValue: _mode,
          onValueChanged: (dynamic val) async {
            if (_mode != val) {
              if (val == PickerMode.Camera &&
                  (cameras.isEmpty || !_isCameraPermissionOK)) {
                _switchScreenMode();
              } else if (val == PickerMode.Album) {
                _switchScreenMode();
                await _initPhotoGallery();
              }

              setState(() {
                _mode = val as int;
              });
            }
          });
    }
    return const SizedBox();
  }

  /// Build exposure mode control widget.
  Widget _exposureModeControlRowWidget() {
    if (_controller2?.value == null) return const SizedBox();

    final ButtonStyle styleAuto = TextButton.styleFrom(
      primary: _controller2?.value.exposureMode == ExposureMode.auto
          ? Colors.orange
          : Colors.white,
    );
    final ButtonStyle styleLocked = TextButton.styleFrom(
      primary: _controller2?.value.exposureMode == ExposureMode.locked
          ? Colors.orange
          : Colors.white,
    );

    const textStyle = TextStyle(color: Colors.white);
    return SizeTransition(
      sizeFactor: _exposureModeControlRowAnimation,
      child: ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        child: Container(
          color: Colors.transparent,
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Text(_minAvailableExposureOffset.toString(),
                      style: textStyle),
                  Slider(
                    value: _currentExposureOffset,
                    min: _minAvailableExposureOffset,
                    max: _maxAvailableExposureOffset,
                    divisions: 16,
                    label: _currentExposureOffset.toString(),
                    activeColor: Colors.white,
                    inactiveColor: Colors.white,
                    onChanged: _minAvailableExposureOffset ==
                            _maxAvailableExposureOffset
                        ? null
                        : _setExposureOffset,
                  ),
                  Text(_maxAvailableExposureOffset.toString(),
                      style: textStyle),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Set exposure mode button.
  void _onSetExposureModeButtonPressed(ExposureMode mode) {
    _setExposureMode(mode).then((_) {
      if (mounted) setState(() {});
    });
  }

  /// Set exposure mode button.
  Future<void> _setExposureMode(ExposureMode mode) async {
    if (_controller2 == null) {
      return;
    }

    try {
      await _controller2!.setExposureMode(mode);
    } on CameraException catch (_) {
      rethrow;
    }
  }

  /// Set exposure offset.
  Future<void> _setExposureOffset(double offset) async {
    if (_controller2 == null) {
      return;
    }

    setState(() {
      _currentExposureOffset = offset;
    });
    try {
      // The return value is not used or needed, let's no assign it to offset.
      await _controller2!.setExposureOffset(offset);
    } on CameraException catch (_) {
      rethrow;
    }
  }
}

class FaceDetectorPainter extends CustomPainter{
  final List<Face>faces;
  final Size absoluteImageSize;
  final InputImageRotation rotation;

  FaceDetectorPainter(this.faces,this.absoluteImageSize,this.rotation);


  @override
  void paint(final Canvas canvas,final Size size){
    final Paint paint=Paint()
      ..style=PaintingStyle.stroke
      ..strokeWidth=1.0
      ..color=Colors.blue;
    for(final Face face in faces){
      print(face);
      canvas.drawRect(face.boundingBox.topLeft/1.75+Offset(0,65) & face
          .boundingBox.size/1.7,paint);
    }
  }

  @override
  bool shouldRepaint(final FaceDetectorPainter oldDelegate){
    return oldDelegate.absoluteImageSize!=absoluteImageSize||oldDelegate.faces!=faces;
  }
}
