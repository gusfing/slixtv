import '../../features/auth/data/models.dart' show Category;

/// Sorts categories according to the defined priority:
/// 1. English
/// 2. Hindi
/// 3. Urdu
/// 4. Others (alphabetically)
List<Category> sortCategoriesByLanguage(List<Category> categories) {
  // Sort in-place or create a copy? Creating a copy is safer.
  final sortedList = List<Category>.from(categories);

  sortedList.sort((a, b) {
    final titleA = a.title.toLowerCase();
    final titleB = b.title.toLowerCase();

    final priorityA = _getPriority(titleA);
    final priorityB = _getPriority(titleB);

    if (priorityA != priorityB) {
      return priorityA.compareTo(priorityB);
    }

    // If they have the same priority, sort alphabetically
    return titleA.compareTo(titleB);
  });

  return sortedList;
}

int _getPriority(String title) {
  if (title.contains('english')) return 1;
  if (title.contains('hindi')) return 2;
  if (title.contains('urdu')) return 3;
  return 4;
}
