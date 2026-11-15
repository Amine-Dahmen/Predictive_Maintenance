import 'package:flutter/foundation.dart';

import '../models/app_role.dart';

class RoleHomeViewModel extends ChangeNotifier {
  RoleHomeViewModel(this.role);

  final AppRole role;
  int selectedIndex = 0;

  void selectPage(int index) {
    selectedIndex = index;
    notifyListeners();
  }
}
