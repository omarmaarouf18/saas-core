import 'package:frontend/ui/qd_launch.dart';

/// Records what the pages try to open (FE-V2-CONSUME). [opens] decides per
/// link whether an app "opened" it (default: none, so the copy fallback
/// runs).
class FakeLauncher extends QdLauncher {
  FakeLauncher({this.opens});

  bool Function(Uri uri)? opens;
  final List<Uri> tried = [];

  @override
  Future<bool> open(Uri uri) async {
    tried.add(uri);
    return opens?.call(uri) ?? false;
  }
}
