part of 'reader.dart';

class ComicImage extends StatefulWidget {
  /// Modified from flutter Image
  ComicImage({
    required ImageProvider image,
    super.key,
    double scale = 1.0,
    this.semanticLabel,
    this.excludeFromSemantics = false,
    this.width,
    this.height,
    this.color,
    this.opacity,
    this.colorBlendMode,
    this.fit,
    this.alignment = Alignment.center,
    this.repeat = ImageRepeat.noRepeat,
    this.centerSlice,
    this.matchTextDirection = false,
    this.gaplessPlayback = false,
    this.filterQuality = FilterQuality.medium,
    this.isAntiAlias = false,
    Map<String, String>? headers,
    int? cacheWidth,
    int? cacheHeight,
    this.onInit,
    this.onDispose,
  }) : image = ResizeImage.resizeIfNeeded(cacheWidth, cacheHeight, image),
       assert(cacheWidth == null || cacheWidth > 0),
       assert(cacheHeight == null || cacheHeight > 0);

  final ImageProvider image;

  final String? semanticLabel;

  final bool excludeFromSemantics;

  final double? width;

  final double? height;

  final bool gaplessPlayback;

  final bool matchTextDirection;

  final Rect? centerSlice;

  final ImageRepeat repeat;

  final AlignmentGeometry alignment;

  final BoxFit? fit;

  final BlendMode? colorBlendMode;

  final FilterQuality filterQuality;

  final Animation<double>? opacity;

  final Color? color;

  final bool isAntiAlias;

  final void Function(State<ComicImage> state)? onInit;

  final void Function(State<ComicImage> state)? onDispose;

  static void clear() => _ComicImageState.clear();

  @override
  State<ComicImage> createState() => _ComicImageState();
}

class _ComicImageState extends State<ComicImage> with WidgetsBindingObserver {
  Uint8List? _upscaledBytes;
  bool _isUpscaling = false;
  ImageStream? _imageStream;
  ImageInfo? _imageInfo;
  ImageChunkEvent? _loadingProgress;
  bool _isListeningToStream = false;
  late bool _invertColors;
  int? _frameNumber;
  bool _wasSynchronouslyLoaded = false;
  late DisposableBuildContext<State<ComicImage>> _scrollAwareContext;
  Object? _lastException;
  ImageStreamCompleterHandle? _completerHandle;

  static final Map<int, Size> _cache = {};

  bool get hasAnime4KResult => _upscaledBytes != null;

  bool get isAnime4KProcessing => _isUpscaling;

  String? get readerImageKey {
    final source = _getAnime4KSourceProvider(widget.image);
    if (source is ReaderImageProvider) {
      return source.imageKey;
    }
    return null;
  }

  void _notifyReaderScaffold() {
    if (!mounted) {
      return;
    }
    context.readerScaffold.update();
  }

  static clear() => _cache.clear();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollAwareContext = DisposableBuildContext<State<ComicImage>>(this);
    widget.onInit?.call(this);
  }

  @override
  void dispose() {
    assert(_imageStream != null);
    WidgetsBinding.instance.removeObserver(this);
    _stopListeningToStream();
    _completerHandle?.dispose();
    _scrollAwareContext.dispose();
    _replaceImage(info: null);
    widget.onDispose?.call(this);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    _updateInvertColors();
    _resolveImage();

    if (TickerMode.valuesOf(context).enabled) {
      _listenToStream();
    } else {
      _stopListeningToStream(keepStreamAlive: true);
    }

    _triggerImageUpscale();

    super.didChangeDependencies();
  }

  Future<void> _triggerImageUpscale() async {
    if (!mounted || _isUpscaling || _upscaledBytes != null) {
      if (mounted && (_isUpscaling || _upscaledBytes != null)) {
        Log.info(
          'Anime4K',
          'skip trigger: upscaling=$_isUpscaling hasUpscaledBytes=${_upscaledBytes != null}',
        );
      }
      return;
    }
    final enabled = _getAnime4KSetting<bool>('enableAnime4K') ?? false;
    if (!enabled) {
      return;
    }

    final source = _getAnime4KSourceProvider(widget.image);
    if (source == null) {
      Log.info(
        'Anime4K',
        'skip trigger: unsupported image provider ${widget.image.runtimeType}',
      );
      return;
    }

    final enableNetwork =
        _getAnime4KSetting<bool>('enableAnime4KForNetwork') ?? false;
    if (source is ReaderImageProvider &&
        !source.imageKey.startsWith('file://') &&
        !enableNetwork) {
      Log.info(
        'Anime4K',
        'skip trigger: network reader image disabled imageKey=${source.imageKey}',
      );
      return;
    }

    Log.info(
      'Anime4K',
      'trigger start: enabled=$enabled network=$enableNetwork widgetProvider=${widget.image.runtimeType} sourceProvider=${source.runtimeType} cacheKey=${_buildCacheKey(source)}',
    );

    final imageBytes = await _loadSourceBytes(source);
    final cacheKey = _buildCacheKey(source);
    if (!mounted || imageBytes == null || cacheKey == null) {
      Log.info(
        'Anime4K',
        'skip trigger: mounted=$mounted imageBytes=${imageBytes?.length ?? 0} cacheKey=$cacheKey',
      );
      return;
    }

    Log.info(
      'Anime4K',
      'loaded source bytes: cacheKey=$cacheKey bytes=${imageBytes.length}',
    );

    setState(() {
      _isUpscaling = true;
    });
    _notifyReaderScaffold();

    final scaleFactor =
        (_getAnime4KSetting<num>('anime4KScaleFactor'))?.toDouble() ?? 2.0;
    final pushStrength =
        (_getAnime4KSetting<num>('anime4KPushStrength'))?.toDouble() ?? 0.31;
    final pushGradStrength =
        (_getAnime4KSetting<num>('anime4KPushGradStrength'))?.toDouble() ?? 1.0;

    final result = await Anime4KService.instance.processImage(
      imageBytes: imageBytes,
      cacheKey: cacheKey,
      scaleFactor: scaleFactor,
      pushStrength: pushStrength,
      pushGradStrength: pushGradStrength,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _upscaledBytes = result;
      _isUpscaling = false;
    });
    _notifyReaderScaffold();

    Log.info(
      'Anime4K',
      'trigger end: cacheKey=$cacheKey resultBytes=${result?.length ?? 0} applied=${result != null}',
    );
  }

  T? _getAnime4KSetting<T>(String key) {
    final sourceKey = context.reader.type.comicSource?.key;
    if (sourceKey != null) {
      return appdata.settings.getReaderSetting(
            context.reader.cid,
            sourceKey,
            key,
          )
          as T?;
    }
    return appdata.settings.getDeviceReaderSetting(key) as T?;
  }

  ImageProvider? _getAnime4KSourceProvider(ImageProvider provider) {
    if (provider is ResizeImage) {
      return provider.imageProvider;
    }
    return provider;
  }

  Future<Uint8List?> _loadSourceBytes(ImageProvider source) async {
    if (source is FileImage) {
      return source.file.readAsBytes();
    }
    if (source is MemoryImage) {
      return source.bytes;
    }
    if (source is ReaderImageProvider) {
      return source.load(StreamController<ImageChunkEvent>(), () {});
    }
    Log.info(
      'Anime4K',
      'unsupported source provider for bytes ${source.runtimeType}',
    );
    return null;
  }

  String? _buildCacheKey(ImageProvider source) {
    if (source is FileImage) {
      return source.file.path;
    }
    if (source is MemoryImage) {
      return 'memory_${source.bytes.length}_${source.hashCode}';
    }
    if (source is ReaderImageProvider) {
      return source.key;
    }
    return null;
  }

  @override
  void didUpdateWidget(ComicImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.image != oldWidget.image) {
      Log.info(
        'Anime4K',
        'image provider changed: old=${oldWidget.image.runtimeType} new=${widget.image.runtimeType}',
      );
      _upscaledBytes = null;
      _isUpscaling = false;
      _resolveImage();
      _notifyReaderScaffold();
      _triggerImageUpscale();
    }
  }

  @override
  void didChangeAccessibilityFeatures() {
    super.didChangeAccessibilityFeatures();
    setState(() {
      _updateInvertColors();
    });
  }

  @override
  void reassemble() {
    _resolveImage(); // in case the image cache was flushed
    super.reassemble();
  }

  bool containsPoint(Offset point) {
    if (!mounted) {
      return false;
    }
    var renderBox = context.findRenderObject() as RenderBox;
    var localPoint = renderBox.globalToLocal(point);
    return renderBox.paintBounds.contains(localPoint);
  }

  void _updateInvertColors() {
    _invertColors =
        MediaQuery.maybeInvertColorsOf(context) ??
        SemanticsBinding.instance.accessibilityFeatures.invertColors;
  }

  void _resolveImage() {
    final ScrollAwareImageProvider provider = ScrollAwareImageProvider<Object>(
      context: _scrollAwareContext,
      imageProvider: widget.image,
    );
    final ImageStream newStream = provider.resolve(
      createLocalImageConfiguration(
        context,
        size: widget.width != null && widget.height != null
            ? Size(widget.width!, widget.height!)
            : null,
      ),
    );
    _updateSourceStream(newStream);
  }

  ImageStreamListener? _imageStreamListener;

  ImageStreamListener _getListener({bool recreateListener = false}) {
    if (_imageStreamListener == null || recreateListener) {
      _lastException = null;
      _imageStreamListener = ImageStreamListener(
        _handleImageFrame,
        onChunk: _handleImageChunk,
        onError: (Object error, StackTrace? stackTrace) {
          setState(() {
            _lastException = error;
          });
          _onImageLoadError();
        },
      );
    }
    return _imageStreamListener!;
  }

  void _onImageLoadError() {
    final provider = widget.image;
    if (provider is ReaderImageProvider) {
      var cacheKey =
          "loadComicPages@${provider.sourceKey}@${provider.cid}@${provider.eid}";
      CacheManager().delete(cacheKey);
    }
  }

  void _handleImageFrame(ImageInfo imageInfo, bool synchronousCall) {
    setState(() {
      _replaceImage(info: imageInfo);
      _loadingProgress = null;
      _lastException = null;
      _frameNumber = _frameNumber == null ? 0 : _frameNumber! + 1;
      _wasSynchronouslyLoaded = _wasSynchronouslyLoaded | synchronousCall;
    });
  }

  void _handleImageChunk(ImageChunkEvent event) {
    setState(() {
      _loadingProgress = event;
      _lastException = null;
    });
  }

  void _replaceImage({required ImageInfo? info}) {
    final ImageInfo? oldImageInfo = _imageInfo;
    SchedulerBinding.instance.addPostFrameCallback(
      (_) => oldImageInfo?.dispose(),
    );
    _imageInfo = info;
  }

  // Updates _imageStream to newStream, and moves the stream listener
  // registration from the old stream to the new stream (if a listener was
  // registered).
  void _updateSourceStream(ImageStream newStream) {
    if (_imageStream?.key == newStream.key) {
      return;
    }

    if (_isListeningToStream) {
      _imageStream!.removeListener(_getListener());
    }

    if (!widget.gaplessPlayback) {
      setState(() {
        _replaceImage(info: null);
      });
    }

    setState(() {
      _loadingProgress = null;
      _frameNumber = null;
      _wasSynchronouslyLoaded = false;
    });

    _imageStream = newStream;
    if (_isListeningToStream) {
      _imageStream!.addListener(_getListener());
    }
  }

  void _listenToStream() {
    if (_isListeningToStream) {
      return;
    }

    _imageStream!.addListener(_getListener());
    _completerHandle?.dispose();
    _completerHandle = null;

    _isListeningToStream = true;
  }

  /// Stops listening to the image stream, if this state object has attached a
  /// listener.
  ///
  /// If the listener from this state is the last listener on the stream, the
  /// stream will be disposed. To keep the stream alive, set `keepStreamAlive`
  /// to true, which create [ImageStreamCompleterHandle] to keep the completer
  /// alive and is compatible with the [TickerMode] being off.
  void _stopListeningToStream({bool keepStreamAlive = false}) {
    if (!_isListeningToStream) {
      return;
    }

    if (keepStreamAlive &&
        _completerHandle == null &&
        _imageStream?.completer != null) {
      _completerHandle = _imageStream!.completer!.keepAlive();
    }

    _imageStream!.removeListener(_getListener());
    _isListeningToStream = false;
  }

  @override
  Widget build(BuildContext context) {
    if (_lastException != null) {
      // display error and retry button on screen
      return SizedBox(
        height: widget.height == null ? 300 : null,
        width: widget.width == null ? 300 : null,
        child: Center(
          child: SizedBox(
            height: 300,
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: Text(_lastException.toString(), maxLines: 3),
                  ),
                ),
                const SizedBox(height: 4),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Listener(
                    onPointerDown: (details) {
                      GlobalState.find<_ReaderGestureDetectorState>()
                          .ignoreNextTap();
                      setState(() {
                        _loadingProgress = null;
                        _lastException = null;
                      });
                      _resolveImage();
                    },
                    child: SizedBox(
                      width: 84,
                      height: 36,
                      child: Center(
                        child: Text(
                          "Retry".tl,
                          style: TextStyle(color: Colors.blue),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constrains) {
        var width = widget.width;
        var height = widget.height;

        final showAnime4K =
            _upscaledBytes != null &&
            context.readerScaffold.showAnime4KProcessed;

        if (_imageInfo != null) {
          // Record the height and the width of the image
          _cache[widget.image.hashCode] = Size(
            _imageInfo!.image.width.toDouble(),
            _imageInfo!.image.height.toDouble(),
          );
        }

        Size? cacheSize = _cache[widget.image.hashCode];
        if (cacheSize != null) {
          if (width == double.infinity) {
            width = constrains.maxWidth;
            height = width * cacheSize.height / cacheSize.width;
          } else if (height == double.infinity) {
            height = constrains.maxHeight;
            width = height * cacheSize.width / cacheSize.height;
          }
        } else {
          if (width == double.infinity) {
            width = constrains.maxWidth;
            height = 300;
          } else if (height == double.infinity) {
            height = constrains.maxHeight;
            width = 300;
          }
        }

        if (_imageInfo != null) {
          // build image
          Widget originalImage = RawImage(
            // Do not clone the image, because RawImage is a stateless wrapper.
            // The image will be disposed by this state object when it is not needed
            // anymore, such as when it is unmounted or when the image stream pushes
            // a new image.
            image: _imageInfo?.image,
            debugImageLabel: _imageInfo?.debugLabel,
            width: width,
            height: height,
            scale: _imageInfo?.scale ?? 1.0,
            color: widget.color,
            opacity: widget.opacity,
            colorBlendMode: widget.colorBlendMode,
            fit: widget.fit,
            alignment: widget.alignment,
            repeat: widget.repeat,
            centerSlice: widget.centerSlice,
            matchTextDirection: widget.matchTextDirection,
            invertColors: _invertColors,
            isAntiAlias: widget.isAntiAlias,
            filterQuality: widget.filterQuality,
          );

          Widget result;
          if (showAnime4K) {
            result = Stack(
              fit: StackFit.passthrough,
              alignment: Alignment.center,
              children: [
                originalImage,
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  child: Image.memory(
                    _upscaledBytes!,
                    width: width,
                    height: height,
                    color: widget.color,
                    opacity: widget.opacity,
                    colorBlendMode: widget.colorBlendMode,
                    fit: widget.fit,
                    alignment: widget.alignment,
                    repeat: widget.repeat,
                    centerSlice: widget.centerSlice,
                    matchTextDirection: widget.matchTextDirection,
                    gaplessPlayback: true,
                    isAntiAlias: widget.isAntiAlias,
                    filterQuality: widget.filterQuality,
                    excludeFromSemantics: true,
                  ),
                  builder: (context, opacity, child) {
                    return Opacity(opacity: opacity, child: child);
                  },
                ),
              ],
            );
          } else {
            result = originalImage;
          }

          if (!widget.excludeFromSemantics) {
            result = Semantics(
              container: widget.semanticLabel != null,
              image: true,
              label: widget.semanticLabel ?? '',
              child: result,
            );
          }
          result = SizedBox(
            width: width,
            height: height,
            child: Center(child: result),
          );
          return result;
        } else {
          // build progress
          return SizedBox(
            width: width,
            height: height,
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  backgroundColor: context.colorScheme.surfaceContainer,
                  value:
                      (_loadingProgress != null &&
                          _loadingProgress!.expectedTotalBytes != null &&
                          _loadingProgress!.expectedTotalBytes! != 0)
                      ? _loadingProgress!.cumulativeBytesLoaded /
                            _loadingProgress!.expectedTotalBytes!
                      : 0,
                ),
              ),
            ),
          );
        }
      },
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder description) {
    super.debugFillProperties(description);
    description.add(DiagnosticsProperty<ImageStream>('stream', _imageStream));
    description.add(DiagnosticsProperty<ImageInfo>('pixels', _imageInfo));
    description.add(
      DiagnosticsProperty<ImageChunkEvent>('loadingProgress', _loadingProgress),
    );
    description.add(DiagnosticsProperty<int>('frameNumber', _frameNumber));
    description.add(
      DiagnosticsProperty<bool>(
        'wasSynchronouslyLoaded',
        _wasSynchronouslyLoaded,
      ),
    );
  }
}
