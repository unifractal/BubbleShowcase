library bubble_showcase;

import 'package:bubble_showcase/src/slide.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The BubbleShowcase main widget.
class BubbleShowcase extends StatefulWidget {
  /// This showcase identifier. Must be unique across the app.
  final String bubbleShowcaseId;

  /// This showcase version.
  final int bubbleShowcaseVersion;

  /// Whether this showcase should reopen once closed.
  final bool doNotReopenOnClose;

  /// All slides.
  final List<BubbleSlide> bubbleSlides;

  /// The child widget (displayed below the showcase).
  final Widget child;

  /// The counter text (:i is the current slide, :n is the slides count). You can pass null to disable this.
  final String? counterText;

  /// Whether to show a close button.
  final bool showCloseButton;

  /// Duration by which delay showcase initialization.
  final Duration initialDelay;

  /// Wether this showcase should be presented.
  final bool enabled;

  final Function? onCompleted;

  final bool autoStart;

  /// Creates a new bubble showcase instance.
  BubbleShowcase({
    required this.bubbleShowcaseId,
    required this.bubbleShowcaseVersion,
    this.doNotReopenOnClose = false,
    required this.bubbleSlides,
    required this.child,
    this.counterText = ':i/:n',
    this.showCloseButton = true,
    this.initialDelay = Duration.zero,
    this.enabled = true,
    this.onCompleted,
    this.autoStart = true,
    super.key,
  }) : assert(bubbleSlides.isNotEmpty);

  @override
  State<StatefulWidget> createState() => BubbleShowcaseState();

  /// Whether this showcase should be opened.
  Future<bool> get shouldOpenShowcase async {
    if (!enabled) {
      return false;
    }
    if (!doNotReopenOnClose) {
      return true;
    }
    SharedPreferences preferences = await SharedPreferences.getInstance();
    bool? result =
        preferences.getBool('$bubbleShowcaseId.$bubbleShowcaseVersion');
    return result == null || result;
  }
}

/// The BubbleShowcase state.
class BubbleShowcaseState extends State<BubbleShowcase>
    with WidgetsBindingObserver {
  late List<BubbleSlide> bubbleSlides;

  /// The current slide index.
  int currentSlideIndex = -1;

  /// The current slide entry.
  OverlayEntry? currentSlideEntry;

  void _init() {
    bubbleSlides = widget.bubbleSlides;
  }

  @override
  void initState() {
    _init();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (await widget.shouldOpenShowcase) {
        await Future.delayed(widget.initialDelay);
        if (mounted) {
          if (widget.autoStart) {
            goToNextEntryOrClose(0);
          }
        }
      }
    });
    WidgetsBinding.instance.addObserver(this);

    super.initState();
  }

  @override
  void didUpdateWidget(Widget oldWidget) {
    var oldShowcase = oldWidget as BubbleShowcase;

    if (oldShowcase.bubbleSlides != widget.bubbleSlides) {
      _init();
    }

    super.didUpdateWidget(oldWidget);
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<BubbleShowcaseNotification>(
        onNotification: processNotification,
        child: widget.child,
      );

  @override
  void dispose() {
    currentSlideEntry?.remove();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (currentSlideEntry != null) {
        currentSlideEntry!.remove();
        Overlay.of(context)?.insert(currentSlideEntry!);
      }
    });
  }

  /// Starts showcase from the beginning
  void startShowcase() {
    goToNextEntryOrClose(0);
  }

  void appendSlide(BubbleSlide slide) {
    bubbleSlides.add(slide);
  }

  bool processNotification(BubbleShowcaseNotification notif) {
    if (isFinished) return true;
    goToNextEntryOrClose(currentSlideIndex + 1);
    return true;
  }

  /// Returns whether the showcasing is finished.
  bool get isFinished =>
      currentSlideIndex == -1 || currentSlideIndex == bubbleSlides.length;

  /// Allows to go to the next entry (or to close the showcase if needed).
  void goToNextEntryOrClose(int position) {
    currentSlideIndex = position;
    currentSlideEntry?.remove();
    triggerOnExit();

    if (isFinished) {
      currentSlideEntry = null;
      if (widget.doNotReopenOnClose) {
        SharedPreferences.getInstance().then(
          (preferences) => preferences.setBool(
            '${widget.bubbleShowcaseId}.${widget.bubbleShowcaseVersion}',
            false,
          ),
        );
      }
      widget.onCompleted?.call();
    } else {
      if (checkSlideValid(position)) {
        currentSlideEntry = createSlideEntry(position);
        Overlay.of(context)?.insert(currentSlideEntry!);
        triggerOnEnter();
      } else {
        goToNextEntryOrClose(position + 1);
      }
    }
  }

  bool checkSlideValid(int position) {
    if (position >= bubbleSlides.length || position < 0) return false;
    if (bubbleSlides[position] is RelativeBubbleSlide) {
      RelativeBubbleSlide slide = bubbleSlides[position] as RelativeBubbleSlide;
      if (slide.widgetKey.currentContext == null) {
        debugPrint('Skipping slide, key is null');
        return false;
      }
    }

    return true;
  }

  /// Creates the current slide entry.
  OverlayEntry createSlideEntry(int position) => OverlayEntry(
        builder: (context) => bubbleSlides[position].build(
          context,
          widget,
          position,
          (position) {
            setState(() => goToNextEntryOrClose(position));
          },
        ),
      );

  /// Allows to trigger enter callbacks.
  void triggerOnEnter() {
    if (currentSlideIndex >= 0 && currentSlideIndex < bubbleSlides.length) {
      VoidCallback? callback = bubbleSlides[currentSlideIndex].onEnter;
      callback?.call();
    }
  }

  /// Allows to trigger exit callbacks.
  void triggerOnExit() {
    if (currentSlideIndex >= 0 && currentSlideIndex < bubbleSlides.length) {
      VoidCallback? callback = bubbleSlides[currentSlideIndex].onExit;
      callback?.call();
    }
  }
}

/// Notification Used to tell the [BubbleShowcase] to continue the showcase
class BubbleShowcaseNotification extends Notification {
  const BubbleShowcaseNotification();
}
