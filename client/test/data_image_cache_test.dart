import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aos_client/data_image_cache.dart';
import 'package:aos_client/main.dart';

void main() {
  test('collects unique image URLs from image fields only', () {
    final urls = DataImageCache.imageUrlsFrom({
      'metadata': {'data_version': 494},
      'data': {
        'warscroll': [
          {
            'rowImage': 'https://cdn.example/one.jpg',
            'bannerImage': 'https://cdn.example/one.jpg',
            'name': 'https://cdn.example/not-an-image.jpg',
            'imageUrl': 'not a URL',
          },
          {
            'backgroundImage': ' https://cdn.example/two.jpg ',
          },
        ],
      },
    });

    expect(
      urls,
      [
        'https://cdn.example/one.jpg',
        'https://cdn.example/two.jpg',
      ],
    );
  });

  test('rejects a malformed image catalog', () {
    expect(
      () => DataImageCache.imageUrlsFrom({
        'data': {'warscroll': 'invalid'}
      }),
      throwsFormatException,
    );
  });

  testWidgets('shows a separate switch for downloading all images',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const MaterialApp(home: OfflineSettingsPage()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Download the entire database'), findsOneWidget);
    expect(find.text('Download all images'), findsOneWidget);
  });
}
