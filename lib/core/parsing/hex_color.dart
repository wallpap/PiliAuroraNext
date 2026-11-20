int parseOpaqueHexColor(String color) =>
    0xFF000000 | int.parse(color.substring(1), radix: 16);
