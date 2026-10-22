/// 把异常转成可直接展示给用户的文案。
///
/// `'$e'` 会带 `Bad state:` / `FormatException:` 这类类型前缀，对用户没有意义；
/// [StateError] / [FormatException] 直接取 message，其余异常去掉已知前缀。
String errorText(Object error) {
  if (error is StateError) return error.message;
  if (error is FormatException) return error.message;
  final text = error.toString();
  const prefixes = [
    'Bad state: ',
    'Exception: ',
    'FormatException: ',
    'StateError: ',
  ];
  for (final prefix in prefixes) {
    if (text.startsWith(prefix)) return text.substring(prefix.length);
  }
  return text;
}
