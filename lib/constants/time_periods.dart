/* 
 * 班级管理系统 - Class Management System 
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V5.0.2
 * 创建日期 (Created): 2026-07-25 
 * 
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

/// 在校时段定义：key → "时间范围 名称"。
/// 同一类时段合并为一个 key（就餐含早、中、晚三段，上课含上午与下午），
/// 多段时间用"、"连接；名称必须放在最后，便于提取简称。
/// 记录对话框按当前时刻自动预选时段（见 record_dialog.dart 的 _getCurrentPeriod）。
const Map<String, String> timePeriods = {
  'meal': '06:20-07:00、12:30-13:00、18:00-18:40 就餐',
  'morning_reading': '07:00-08:00 早读',
  'class': '08:00-12:30、14:00-16:40 上课',
  'noon_rest': '13:00-14:00 午休',
  'after_school': '16:40-18:00 课后服务',
  'evening_prep': '18:40-19:00 晚修前',
  'evening_study': '19:00-21:30 晚修中',
  'evening_after': '21:30-22:00 晚修后',
  'sleep': '22:00-06:20 就寝',
};

/// 用户自定义的完整时段列表（可增删）；为空时使用出厂 9 段。
List<Map<String, String>> _customPeriods = const [];

/// 过滤非法时段项并归一化字段，返回**新列表**（落库与运行时同一口径）。
///
/// G-9/G-19：此前过滤只在 [applyCustomPeriods] 内做，settings 里仍保存未过滤的
/// 原始列表（落盘与运行时口径不一致），且调用方传入的 List 被直接接管。
List<Map<String, String>> sanitizePeriods(
  List<Map<String, String>> periods,
) {
  // 修复（审计 P2-28）：同一 key 只保留第一条（first-wins）—— 重复 key 会
  // 让时段选择/匹配出现两枚同名项；并与 _parsePeriodList 的口径保持一致。
  final seenKeys = <String>{};
  final result = <Map<String, String>>[];
  for (final item in periods) {
    final key = item['key'] ?? '';
    if (key.isEmpty) continue;
    final label = item['label'] ?? '';
    if (validatePeriodLabel(label.trim()) != null) continue;
    if (!seenKeys.add(key)) continue;
    result.add({'key': key, 'label': label});
  }
  return result;
}

/// 应用完整的自定义时段列表（[{key, label}, ...]；空表示恢复出厂时段）。
void applyCustomPeriods(List<Map<String, String>> periods) {
  // 修复（审查 P2-9）：落库前与设置页**同口径**校验 —— 此前校验只存在于 UI，
  // 从数据包导入的越界/反向/同名时段可以绕过它直接入库（matchPeriodByMinutes 永不命中）。
  _customPeriods = sanitizePeriods(periods);
}

/// 测试用：把时段模块级全局状态重置为出厂（避免测试之间互相串态，见 G-19）。
void resetPeriodsForTest() {
  _customPeriods = const [];
}

/// 出厂时段标签副本（设置页"恢复默认"用）。
Map<String, String> defaultPeriodLabels() => Map<String, String>.from(timePeriods);

/// 当前生效的时段列表（key + 标签），供各处遍历与展示。
List<Map<String, String>> effectivePeriods() {
  if (_customPeriods.isNotEmpty) {
    return _customPeriods
        .map((item) => {'key': item['key']!, 'label': item['label']!})
        .toList();
  }
  return [
    for (final entry in timePeriods.entries)
      {'key': entry.key, 'label': entry.value},
  ];
}

/// 时段标签是否合法："06:20-07:00、12:30-13:00 就餐"。
/// 返回错误提示，合法时返回 null。
String? validatePeriodLabel(String label) {
  final value = label.trim();
  if (value.isEmpty) return '时段内容不能为空';
  final parts = value.split(' ');
  if (parts.length < 2) return '格式应为"时间段 名称"，如 08:00-12:30 上课';
  final name = parts.sublist(1).join(' ').trim();
  if (name.isEmpty) return '时段名称不能为空';
  final ranges = _parseRanges(value);
  if (ranges.isEmpty) return '时间段格式应为 08:00-12:30，多个用、分隔';
  // 修复（审查 P3-8）：起止时间相同（如 08:00-08:00）是明显的输入错误，
  // 此前会被接受，导致该时段永不命中。
  for (final range in ranges) {
    if (range[0] == range[1]) return '时间段的起止时间不能相同';
  }
  return null;
}

/// 按 key 查标签。传入 [periods] 时只用该快照，不读模块级全局态。
///
/// 修复（2026-10-05复查 P0）：Excel 解析/导出已移入 `Isolate.run`，而
/// `_customPeriods` 是**模块级可变全局**——新 isolate
/// 里它们回到出厂值，自定义时段就丢了。所有跨 isolate 的路径必须由主 isolate
/// 先取 [effectivePeriods] 快照再传进来，不能依赖这里的全局。
String? _labelOfKey(String key, [List<Map<String, String>>? periods]) {
  final list = periods ?? effectivePeriods();
  for (final item in list) {
    if (item['key'] == key) return item['label'];
  }
  return null;
}

/// 考勤"全天"时段：不属于日常时段，仅在考勤里使用。
const String allDayPeriodKey = 'all_day';
const String allDayPeriodLabel = '全天';

/// 时段显示名：优先取当前生效的自定义/出厂标签，最后回退 key。
///
/// [periods] 为时段快照（跨isolate 时必传，见 [_labelOfKey] 注释）。
String getTimePeriodName(String key, [List<Map<String, String>>? periods]) {
  if (key == allDayPeriodKey) return allDayPeriodLabel;
  // 修复（审查 五-2）：显示名统一 trim —— 自定义标签带尾随空格时，
  // 不该把空格显示到考勤下拉与记录列表里（与短名的 trim 口径对齐）。
  final label = _labelOfKey(key, periods)?.trim();
  return (label == null || label.isEmpty) ? key : label;
}

String getTimePeriodShortName(String key, [List<Map<String, String>>? periods]) {
  if (key == allDayPeriodKey) return allDayPeriodLabel;
  // 修复（1.10，2026-10-03 审查）：标签尾部带空格时 `split(' ').last` 得到
  // 空串（如 '08:00-09:40 第一节 '），考勤时段下拉里会出现**空白选项**。
  // 统一 trim 后再取尾段，仍为空时回退全名。
  final fullName = _labelOfKey(key, periods)?.trim();
  if (fullName != null && fullName.isNotEmpty) {
    final short = fullName.split(' ').last.trim();
    return short.isEmpty ? fullName : short;
  }
  return key;
}

/// 考勤可选的时间段：全天 + 当前生效的各时段（key + 显示名）。
List<Map<String, String>> attendancePeriodOptions() => [
      {'key': allDayPeriodKey, 'label': allDayPeriodLabel},
      for (final item in effectivePeriods())
        {'key': item['key']!, 'label': getTimePeriodShortName(item['key']!)},
    ];

/// 考勤时间段排序用的序号（全天最前，其后按当前时段顺序；未知排最后）。
int attendancePeriodOrder(String key) {
  if (key == allDayPeriodKey) return 0;
  final options = attendancePeriodOptions();
  for (var i = 0; i < options.length; i++) {
    if (options[i]['key'] == key) return i;
  }
  return options.length;
}

/// 把标签里的时间段解析为 [起, 止] 分钟数区间（支持跨零点，如 22:00-06:20）。
List<List<int>> _parseRanges(String label) {
  final ranges = <List<int>>[];
  final timePart = label.trim().split(' ').first;
  for (final segment in timePart.split('、')) {
    final bounds = segment.split('-');
    if (bounds.length != 2) continue;
    final start = _toMinutes(bounds[0]);
    final end = _toMinutes(bounds[1]);
    if (start == null || end == null) continue;
    ranges.add([start, end]);
  }
  return ranges;
}

int? _toMinutes(String text) {
  final parts = text.trim().split(':');
  if (parts.length != 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
  return hour * 60 + minute;
}

/// 按当前时刻（0 点起算的分钟数）匹配时段 key，供记录对话框自动预选；
/// 时间落在两个时段之间的空隙时返回 null（不猜测）。
String? matchPeriodByMinutes(int minutes) {
  for (final item in effectivePeriods()) {
    final key = item['key']!;
    final label = item['label']!;
    for (final range in _parseRanges(label)) {
      final start = range[0];
      final end = range[1];
      final matched = start <= end
          ? (minutes >= start && minutes < end)
          : (minutes >= start || minutes < end); // 跨零点
      if (matched) return key;
    }
  }
  return null;
}

/// 解析 "HH:mm" / "HH:mm:ss" 为自 0 点起的分钟数；非法返回 null。
int? minutesOfTimeText(String text) {
  final parts = text.trim().split(':');
  if (parts.length < 2) return null;
  return _toMinutes('${parts[0]}:${parts[1]}');
}

/// 时刻 [minutes] 是否落在 [periodKey] 的"跨零点后半段"（次日凌晨那一截）。
/// 例：就寝 22:00-06:20 —— 00:30 属于后半段（归属应为前一天），23:00 不属于。
bool isAfterMidnightPartOfPeriod(int minutes, String periodKey) {
  if (periodKey.isEmpty) return false;
  for (final item in effectivePeriods()) {
    if (item['key'] != periodKey) continue;
    for (final range in _parseRanges(item['label']!)) {
      // 只有跨零点的时段（起点 > 终点）才有"后半段"。
      if (range[0] > range[1] && minutes < range[1]) return true;
    }
  }
  return false;
}

/// 记录/考勤的**归属日**：跨零点时段的"次日凌晨"部分归属到**前一天**
/// （入睡那天）。例如凌晨 00:30 记的就寝，应算作前一天，否则同一段就寝
/// 会被拆到两天，历史列表与统计都会错位。非跨零点时段返回 [now] 当天。
DateTime attributionDay(DateTime now, String? periodKey) {
  final day = DateTime(now.year, now.month, now.day);
  if (periodKey == null || periodKey.isEmpty) return day;
  final minutes = now.hour * 60 + now.minute;
  if (isAfterMidnightPartOfPeriod(minutes, periodKey)) {
    return DateTime(now.year, now.month, now.day - 1);
  }
  return day;
}

/// [key] 是否是**当前生效的时段键**（含"全天"；空键视为合法，
/// 表示"未标注"，由记录侧规整）。
///
/// X-30：批量写入里的 `periodKey` 此前不校验 —— 未知键会让记录挂在
/// "幽灵时段"下（历史/导出/统计里永远显示不出来）。
bool isKnownPeriodKey(String key) {
  if (key.isEmpty) return true;
  if (key == allDayPeriodKey) return true;
  for (final item in effectivePeriods()) {
    if (item['key'] == key) return true;
  }
  return false;
}

/// 记录在表格/明细里展示用的时段名：优先用当前生效的时段名称，
/// 这样自定义改名后导出与明细会同步更新；时段为空（如导入的外部数据）
/// 时退回记录里保存的名称。
///
/// 修复（审计 P2-32）：时段 key 已失效（如自定义时段被删除）时同样退回
/// 记录里保存的名称 —— 此前会显示原始 key（如 `custom_xxx`），而不是
/// 当初录入的时段名。
String periodNameForRecord(String periodKey, String storedName,
    [List<Map<String, String>>? periods]) {
  if (periodKey.isEmpty) {
    return storedName.isNotEmpty ? storedName : periodKey;
  }
  final resolved = getTimePeriodName(periodKey, periods);
  // getTimePeriodName 认不出 key 时会原样回退成 key 本身。
  if (resolved.isNotEmpty && resolved != periodKey) return resolved;
  return storedName.isNotEmpty ? storedName : resolved;
}

/// 按名称反查时段 key，供导入表格时还原时段：
/// 支持完整标签（"08:00-12:30、14:00-16:40 上课"）与简称（"上课"）；
/// 无法识别时返回空字符串。
String matchTimePeriodKey(String name, [List<Map<String, String>>? periods]) {
  final value = name.trim();
  if (value.isEmpty) return '';
  // 审计 P1-4：导出时"全天"记录的时段列写的是 [allDayPeriodLabel]，回导时
  // 这里必须能还原成 [allDayPeriodKey]。此前只遍历日常时段，全天一律返回空
  // 字符串 —— 导入判重键里的时段为空、而库里存的是 `all_day`，两边永不相等，
  // 同一份导出文件反复回导会成倍产生重复记录。
  if (value == allDayPeriodLabel) return allDayPeriodKey;
  // 修复（审查 P2-10）：与 getTimePeriodShortName(1.10 修复) 同口径 ——
  // 标签先 trim 再取简称，否则带尾随/连续空格的自定义标签反查失败，
  // 导入的时段会静默落到空 key。
  // 修复（2026-10-05 复查 P0）：[periods] 为跨 isolate 传入的时段快照，
  // 见 [_labelOfKey] 注释 —— 缺失时后台 isolate 认不出任何自定义时段。
  for (final item in periods ?? effectivePeriods()) {
    final label = item['label']!.trim();
    final short = label.split(' ').last.trim();
    if (value == label || value == short) {
      return item['key']!;
    }
  }
  return '';
}
