import 'package:flutter/material.dart';
import '../controller/reading_controller.dart';
import '../models/reading_settings.dart';

class ReaderView extends StatefulWidget {
  final ReadingController controller;

  const ReaderView({super.key, required this.controller});

  @override
  State<ReaderView> createState() => _ReaderViewState();
}

class _ReaderViewState extends State<ReaderView> {
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    widget.controller.addListener(_onControllerUpdate);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerUpdate);
    _pageController.dispose();
    super.dispose();
  }

  void _onControllerUpdate() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.controller.book;
    if (book == null) {
      return const Center(child: Text('No book loaded'));
    }

    final chapter = book.currentChapter;
    if (chapter == null) {
      return const Center(child: Text('No chapters available'));
    }

    final settings = widget.controller.settings;
    final content = chapter.content;

    return Container(
      color: settings.backgroundColor,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                content,
                style: TextStyle(
                  fontSize: settings.fontSize,
                  fontWeight: settings.fontWeight,
                  height: settings.lineHeight,
                  color: settings.textColor,
                  fontFamily: settings.fontFamily,
                ),
              ),
            ),
          ),
          _buildNavigationBar(),
        ],
      ),
    );
  }

  Widget _buildNavigationBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: widget.controller.canGoPrevious
                ? () => widget.controller.previousPage()
                : null,
          ),
          Text(
            'Page ${widget.controller.currentPage + 1}',
            style: const TextStyle(fontSize: 14),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward),
            onPressed: widget.controller.canGoNext
                ? () => widget.controller.nextPage()
                : null,
          ),
        ],
      ),
    );
  }
}
