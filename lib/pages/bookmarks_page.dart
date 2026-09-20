import 'package:flutter/material.dart';
import '../map/map_strategy.dart';
import '../models/location_info.dart';
import '../persistence/location_bookmark.dart';

/// 历史列表返回给 HomePage 的结果：选了哪条 + 执行 go 还是 run。
enum BookmarkAction { go, run }

class BookmarkResult {
  final LocationBookmark bookmark;
  final BookmarkAction action;
  const BookmarkResult({required this.bookmark, required this.action});
}

/// "历史收藏位置"全屏 List。
///
/// 行为契约（需求细节）：
///  - 每行默认：地点名 + 经纬度 + 保存时间 + 折叠图标；
///  - 点行：展开/收起该行（同时只允许一行展开）；
///  - 展开后行末追加 Go / Delete 按钮：
///      - Go：[_strategy].moveCamera 跳过去 → 关闭本页面（pop 本页）；
///      - Delete：删除 → setState 刷新 List；
///  - 列表为空：显示"还没有保存的位置"占位。
///  - 加载中：显示进度圈。
class BookmarksPage extends StatefulWidget {
  final MapStrategy strategy;

  const BookmarksPage({super.key, required this.strategy});

  @override
  State<BookmarksPage> createState() => _BookmarksPageState();
}

class _BookmarksPageState extends State<BookmarksPage> {
  List<LocationBookmark> _bookmarks = const [];
  /// 用户展开的行 id。null = 无展开；else = 只允许一行展开。
  String? _expandedId;
  /// 当前被勾选 "always" 的书签 id（null = 无）。全局单选。
  String? _alwaysId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await LocationBookmarks.readAll();
    final alwaysId = await LocationBookmarks.readAlwaysId();
    if (!mounted) return;
    setState(() {
      _bookmarks = list;
      _alwaysId = alwaysId;
      _loading = false;
    });
  }

  Future<void> _onGo(LocationBookmark b) async {
    // ★ 修复 List 不关闭的 bug（最终版）：
    // 之前的实现是 await moveCamera() + 200ms timeout + 再 Navigator.pop(b)。
    // 问题：csp_amap_flutter_map 的 _controller.moveCamera 是 channel 调用，
    // 在 native controller 重建中 / channel 线程阻塞的场景下可能 200ms timeout
    // 之后才返回值，期间因 microtask 调度，赋值 + pop 时序不可靠，List
    // 偶尔关不掉。
    //
    // 稳妥写法：先 pop 把 List 立即关掉，再 fire-and-forget moveCamera。
    //  1. List 用户感知"立刻关闭"（同步）；
    //  2. moveCamera 跳图由 HomePage._openBookmarksList 拿 picked 后再走一次
    //     兜底，那时候 widget 已经 rebuild，channel 一定可用。
    //  3. 若 BookmarksPage 自身能立刻跳图（理想情况），HomePage 兜底也只是一次
    //     同坐标的 moveCamera，无视觉副作用。
    if (!mounted) return;
    Navigator.of(context).pop(
      BookmarkResult(bookmark: b, action: BookmarkAction.go),
    );
    // 不 await，让它后台跑；这条 fire-and-forget 在 pop 之后不影响 List 关闭。
    // 失败也无所谓，HomePage._openBookmarksList 会兜底。
    // ignore: unawaited_futures
    widget.strategy.moveCamera(
      LocationInfo(latitude: b.latitude, longitude: b.longitude),
    );
  }

  /// Run：与 go 相同的跳图逻辑 + 应用到系统，完整流程交给 HomePage 处理。
  Future<void> _onRun(LocationBookmark b) async {
    if (!mounted) return;
    Navigator.of(context).pop(
      BookmarkResult(bookmark: b, action: BookmarkAction.run),
    );
  }

  Future<void> _onDelete(LocationBookmark b) async {
    await LocationBookmarks.delete(b.id);
    // 若删的是 always 那条，同时清掉 always 标记，避免启动时找不到书签。
    if (_alwaysId == b.id) {
      await LocationBookmarks.writeAlwaysId(null);
    }
    if (!mounted) return;
    if (_expandedId == b.id) {
      setState(() => _expandedId = null);
    }
    await _load();
  }

  /// 勾选/取消 "always"。单选语义由 `_alwaysId == b.id` 天然保证。
  Future<void> _onToggleAlways(LocationBookmark b, bool? value) async {
    final String? next = (value == true) ? b.id : null;
    setState(() => _alwaysId = next);
    await LocationBookmarks.writeAlwaysId(next);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('历史位置')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _bookmarks.isEmpty
              ? const Center(
                  child: Text(
                    '还没有保存的位置',
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                )
              : ListView.separated(
                  itemCount: _bookmarks.length,
                  separatorBuilder: (_, __) => const Divider(height: 0),
                  itemBuilder: (_, i) {
                    final b = _bookmarks[i];
                    final isExpanded = _expandedId == b.id;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.place, color: Colors.blue),
                          title: Text(
                            b.displayText,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '${b.latitude.toStringAsFixed(6)}, '
                            '${b.longitude.toStringAsFixed(6)}\n'
                            '保存于 ${_fmtTime(b.savedAt)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          isThreeLine: true,
                          trailing: Icon(
                            isExpanded
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                          ),
                          onTap: () {
                            setState(() {
                              _expandedId = isExpanded ? null : b.id;
                            });
                          },
                        ),
                        if (isExpanded)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: Wrap(
                              alignment: WrapAlignment.end,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                TextButton.icon(
                                  onPressed: () => _onGo(b),
                                  icon: const Icon(
                                    Icons.directions,
                                    color: Colors.green,
                                  ),
                                  label: const Text('Go'),
                                ),
                                TextButton.icon(
                                  onPressed: () => _onDelete(b),
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.red,
                                  ),
                                  label: const Text('Delete'),
                                ),
                                TextButton.icon(
                                  onPressed: () => _onRun(b),
                                  icon: const Icon(
                                    Icons.play_circle_outline,
                                    color: Colors.blue,
                                  ),
                                  label: const Text('Run'),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Checkbox(
                                      value: _alwaysId == b.id,
                                      onChanged: (v) => _onToggleAlways(b, v),
                                    ),
                                    const Text('always'),
                                  ],
                                ),
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                ),
    );
  }

  /// 格式：YYYY-MM-DD HH:MM。
  static String _fmtTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}';
  }
}
