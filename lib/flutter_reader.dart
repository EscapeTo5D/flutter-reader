export 'src/core/models/book.dart';
export 'src/core/models/reading_settings.dart';
export 'src/core/models/reading_settings_codec.dart';
export 'src/core/models/bookmark.dart';
export 'src/core/models/chapter_meta.dart';
export 'src/core/models/chapter_source.dart';
export 'src/core/controller/reading_controller.dart';
export 'src/core/content_processor.dart';
export 'src/core/storage/reader_repository.dart';
export 'src/core/storage/reading_style_preset.dart';
export 'src/core/storage/cached_chapter.dart';
export 'src/core/storage/cached_chapter_source.dart';
export 'src/core/storage/reader_user.dart';
export 'src/core/storage/reading_progress.dart';
export 'src/core/storage/sqflite_reader_repository.dart';
export 'src/reader/entities/text_page.dart';
export 'src/reader/entities/column.dart';
export 'src/reader/engine/page_engine.dart';
export 'src/reader/engine/paginate_isolate.dart';
export 'src/reader/widgets/reader_view.dart';
export 'src/reader/widgets/read_menu.dart';
export 'src/reader/widgets/page_view.dart';
export 'src/reader/widgets/chapter_list_page.dart';
export 'src/reader/widgets/legado_icons.dart';
export 'src/reader/widgets/search_menu.dart';
export 'src/reader/widgets/text_selection_toolbar.dart'
    show ReaderTextSelectionToolbar;

// ─────────── 朗读(TTS)子系统 ───────────
export 'src/aloud/aloud_controller.dart';
export 'src/aloud/aloud_engine.dart';
export 'src/aloud/aloud_cursor.dart';
export 'src/aloud/aloud_settings.dart';
export 'src/aloud/text_slicer.dart';
export 'src/aloud/http_tts_config.dart';
export 'src/aloud/audio_handler.dart';
export 'src/core/storage/http_tts_source.dart';
export 'src/reader/widgets/read_aloud_dialog.dart' show showReadAloudDialog;
