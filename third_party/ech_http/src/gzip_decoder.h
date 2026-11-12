#ifndef ECH_HTTP_GZIP_DECODER_H
#define ECH_HTTP_GZIP_DECODER_H
#include <zlib.h>
#include <limits>

// Decode on the native worker, before the delivery budget and body size limit.
// Unlike curl's generic decoder, the caller selects only Content-Encoding:
// gzip (dart:io semantics), and concatenated gzip members are supported.
class GzipDecoder {
  z_stream stream_{};
  bool initialized_ = false;
  bool ended_ = false;
  const char *error_ = nullptr;
  bool fail(const char *message) { error_ = message; return false; }
public:
  GzipDecoder() = default;
  GzipDecoder(const GzipDecoder &) = delete;
  GzipDecoder &operator=(const GzipDecoder &) = delete;
  ~GzipDecoder() { if (initialized_) inflateEnd(&stream_); }

  const char *error() const { return error_; }

  // False if emit declines or the input is invalid; only the latter sets error().
  template <typename Emit>
  bool write(const char *data, size_t length, Emit emit) {
    if (!length) return true;
    if (length > std::numeric_limits<uInt>::max())
      return fail("Gzip input chunk is too large");
    if (!initialized_) {
      // Dart's gzip decoder also accepts the zlib framing.
      if (inflateInit2(&stream_, MAX_WBITS + 32) != Z_OK)
        return fail("Unable to initialize gzip decoder");
      initialized_ = true;
    }
    stream_.next_in = reinterpret_cast<Bytef *>(const_cast<char *>(data));
    stream_.avail_in = static_cast<uInt>(length);
    unsigned char output[16 * 1024];
    do {
      if (ended_) {
        if (inflateReset(&stream_) != Z_OK)
          return fail("Unable to reset gzip decoder");
        ended_ = false;
      }
      const auto available = stream_.avail_in;
      stream_.next_out = output;
      stream_.avail_out = sizeof(output);
      const int result = inflate(&stream_, Z_NO_FLUSH);
      if (result != Z_OK && result != Z_STREAM_END && result != Z_BUF_ERROR)
        return fail("Invalid gzip response body");
      const auto produced = sizeof(output) - stream_.avail_out;
      if (produced && !emit(reinterpret_cast<const char *>(output), produced)) return false;
      ended_ = result == Z_STREAM_END;
      if (ended_ && !stream_.avail_in) break;
      if (!produced && available == stream_.avail_in) {
        if (stream_.avail_in) return fail("Invalid gzip response body");
        break;
      }
    } while (stream_.avail_in || !stream_.avail_out);
    return true;
  }

  void finish() {
    // Empty HTTP bodies, including HEAD/204/304, are valid without gzip frames.
    if (initialized_ && !ended_) error_ = "Truncated gzip response body";
  }
};
#endif
