import 'package:flutter/material.dart';
import '../controller/reading_controller.dart';
import 'legado_icons.dart';

class SearchMenu extends StatefulWidget {
  final ReadingController controller;

  const SearchMenu({super.key, required this.controller});

  @override
  State<SearchMenu> createState() => _SearchMenuState();
}

class _SearchMenuState extends State<SearchMenu> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.black87),
                  decoration: InputDecoration(
                    hintText: '搜索内容...',
                    hintStyle: const TextStyle(color: Colors.black38),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onSubmitted: (q) => widget.controller.search(q),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: LegadoIcons.search(size: 24, color: Colors.black54),
                onPressed: () => widget.controller.search(_searchController.text),
              ),
              IconButton(
                icon: LegadoIcons.close(size: 24, color: Colors.black54),
                onPressed: () => widget.controller.toggleSearch(),
              ),
            ],
          ),
          if (widget.controller.searchResults.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: LegadoIcons.arrowDropUp(size: 24, color: Colors.black54),
                    onPressed: () => widget.controller.previousSearchResult(),
                  ),
                  Text(
                    '${widget.controller.searchResultIndex + 1}/${widget.controller.searchResults.length}',
                    style: const TextStyle(color: Colors.black87),
                  ),
                  IconButton(
                    icon: LegadoIcons.arrowDropDown(size: 24, color: Colors.black54),
                    onPressed: () => widget.controller.nextSearchResult(),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
