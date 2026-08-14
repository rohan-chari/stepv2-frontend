import 'package:flutter/widgets.dart';

/// Shared visibility authority for full-screen pages whose timers must stop
/// whenever any route (including dialogs/sheets) covers them.
final RouteObserver<ModalRoute<dynamic>> appRouteObserver =
    RouteObserver<ModalRoute<dynamic>>();
