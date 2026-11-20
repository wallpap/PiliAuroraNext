abstract final class FolderAttributes {
  static bool isDefaultFav(int? attr) => attr != null && (attr & 2) == 0;

  static String isPublicFavText(int? attr) =>
      attr == null ? '' : (isPublicFav(attr) ? '公开' : '私密');

  static bool isPublicFav(int attr) => (attr & 1) == 0;

  static bool isFavFolderFull(int attr, int count) =>
      count >= (isDefaultFav(attr) ? 50000 : 1000);
}
