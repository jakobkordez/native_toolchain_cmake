@DefaultAsset('package:add_link/add_link.dart')
library;

import 'dart:ffi';

@Native<Int32 Function(Int32, Int32)>(symbol: 'math_add')
external int mathAdd(int a, int b);
