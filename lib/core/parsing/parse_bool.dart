bool? safeToBool(dynamic value, [String Function()? orString]) =>
    switch (value) {
      bool _ => value,
      int _ => value == 1,
      String _ => orString != null && value == orString(),
      _ => null,
    };
