part of '../state.dart';

/// Null means the user has not chosen yet: a new Android install starts
/// simple, while an install that already has access stays as it was.
@riverpod
bool simpleMode(Ref ref) {
  final stored = ref.watch(
    appSettingProvider.select((state) => state.simpleMode),
  );
  if (stored != null) {
    return stored;
  }
  return system.isAndroid && ref.watch(profilesProvider).isEmpty;
}
