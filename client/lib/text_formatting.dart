String stripMarkdownEmphasis(String value) {
  return value.replaceAll(RegExp(r'[*_]+'), '');
}
