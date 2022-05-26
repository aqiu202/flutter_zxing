#include "common.h"
#include "ReadBarcode.h"
#include "MultiFormatWriter.h"
#include "TextUtfEncoding.h"
#include "BitMatrix.h"
#include "native_zxing.h"
#include <locale>
#include <codecvt>

using namespace ZXing;

extern "C"
{
    FUNCTION_ATTRIBUTE
    char const *version()
    {
        return "1.3.0";
    }

    std::string wstring2string(std::wstring input)
    {
        std::wstring_convert<std::codecvt_utf8<wchar_t>> converter;
        return converter.to_bytes(input);
    }

    FUNCTION_ATTRIBUTE
    struct CodeResult readBarcode(char *bytes, int format, int width, int height, int cropWidth, int cropHeight, int logEnabled)
    {
        long long start = get_now();

        long length = width * height;
        auto *data = new uint8_t[length];
        memcpy(data, bytes, length);

        BarcodeFormats formats = BarcodeFormat(format); // BarcodeFormat::Any;
        DecodeHints hints = DecodeHints().setTryHarder(false).setTryRotate(true).setFormats(formats);
        ImageView image{data, width, height, ImageFormat::Lum};
        if (cropWidth > 0 && cropHeight > 0 && cropWidth < width && cropHeight < height)
        {
            image = image.cropped(width / 2 - cropWidth / 2, height / 2 - cropHeight / 2, cropWidth, cropHeight);
        }
        Result result = ReadBarcode(image, hints);

        struct CodeResult code = {false, nullptr};
        if (result.isValid())
        {
            code.isValid = result.isValid();
            std::string text = wstring2string(result.text());
            code.text = new char[text.length() + 1];
            strcpy(code.text, text.c_str());
            code.format = Format(static_cast<int>(result.format()));
        }

        int evalInMillis = static_cast<int>(get_now() - start);
        if (logEnabled)
        {
            platform_log("zxingRead: %d ms", evalInMillis);
        }
        return code;
    }

    FUNCTION_ATTRIBUTE
    struct CodeResult* readBarcodes(char *bytes, int format, int width, int height, int cropWidth, int cropHeight, int logEnabled)
    {
        long long start = get_now();

        long length = width * height;
        auto *data = new uint8_t[length];
        memcpy(data, bytes, length);

        BarcodeFormats formats = BarcodeFormat(format); // BarcodeFormat::Any;
        DecodeHints hints = DecodeHints().setTryHarder(false).setTryRotate(true).setFormats(formats);
        ImageView image{data, width, height, ImageFormat::Lum};
        if (cropWidth > 0 && cropHeight > 0 && cropWidth < width && cropHeight < height)
        {
            image = image.cropped(width / 2 - cropWidth / 2, height / 2 - cropHeight / 2, cropWidth, cropHeight);
        }
        Results results = ReadBarcodes(image, hints);

        auto *codes = new struct CodeResult [results.size()];
        int i = 0;
        for (auto &result : results)
        {
            struct CodeResult code = {false, nullptr};
            if (result.isValid())
            {
                code.isValid = result.isValid();
                std::string text = wstring2string(result.text());
                code.text = new char[text.length() + 1];
                strcpy(code.text, text.c_str());
                code.format = Format(static_cast<int>(result.format()));
                codes[i] = code;
                i++;
            }
        }

        int evalInMillis = static_cast<int>(get_now() - start);
        if (logEnabled)
        {
            platform_log("zxingRead: %d ms", evalInMillis);
        }
        return codes;
    }

    FUNCTION_ATTRIBUTE
    struct EncodeResult encodeBarcode(char *contents, int width, int height, int format, int margin, int eccLevel, int logEnabled)
    {
        long long start = get_now();

        struct EncodeResult result = {0, contents, Format(format), nullptr, 0, nullptr};
        try
        {
            auto writer = MultiFormatWriter(BarcodeFormat(format)).setMargin(margin).setEccLevel(eccLevel);
            auto bitMatrix = writer.encode(TextUtfEncoding::FromUtf8(std::string(contents)), width, height);
            result.data = ToMatrix<uint32_t>(bitMatrix).data();
            result.length = bitMatrix.width() * bitMatrix.height();
            result.isValid = true;
        }
        catch (const std::exception &e)
        {
            if (logEnabled)
            {
                platform_log("Can't encode text: %s\nError: %s\n", contents, e.what());
            }
            result.error = new char[strlen(e.what()) + 1];
            strcpy(result.error, e.what());
        }

        int evalInMillis = static_cast<int>(get_now() - start);
        if (logEnabled)
        {
            platform_log("zxingEncode: %d ms", evalInMillis);
        }
        return result;
    }
}
