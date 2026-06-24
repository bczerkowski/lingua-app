/// Non-web fallback. On native platforms, prefer share/save plugins.
void downloadText(String filename, String content,
    {String mime = 'text/csv;charset=utf-8'}) {
  throw UnsupportedError('File download is only implemented on web.');
}
