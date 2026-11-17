enum AssetSortOrder {
  newestFirst(apiValue: 'desc', label: 'Newest'),
  oldestFirst(apiValue: 'asc', label: 'Oldest');

  const AssetSortOrder({required this.apiValue, required this.label});

  final String apiValue;
  final String label;
}
