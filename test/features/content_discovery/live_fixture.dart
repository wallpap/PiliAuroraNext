Map<String, dynamic> liveIndex(
  int room, {
  int area = 7,
  int hasMore = 0,
  bool includeFollow = true,
}) => {
  'code': 0,
  'data': {
    'has_more': hasMore,
    'card_list': [
      if (includeFollow)
        {
          'card_type': 'my_idol_v1',
          'card_data': {
            'my_idol_v1': {
              'list': [
                {'roomid': room},
              ],
            },
          },
        },
      {
        'card_type': 'area_entrance_v3',
        'card_data': {
          'area_entrance_v3': {
            'list': [
              {'area_v2_id': area, 'area_v2_parent_id': 8, 'title': '测试分区'},
            ],
          },
        },
      },
      {
        'card_type': 'small_card_v1',
        'card_data': {
          'small_card_v1': {'roomid': room},
        },
      },
    ],
  },
};
Map<String, dynamic> liveSecond(
  List<int> rooms, {
  int? count,
  String? tag = 'online',
}) => {
  'code': 0,
  'data': {
    'count': count ?? rooms.length,
    'list': [
      for (final room in rooms) {'roomid': room},
    ],
    if (tag != null)
      'new_tags': [
        {'name': tag, 'sort_type': tag},
      ],
  },
};
