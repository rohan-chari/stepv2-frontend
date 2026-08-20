import '../services/backend_api_service.dart';

const String kFundedExposureLimitCode = 'FUNDED_EXPOSURE_LIMIT';
const String kFundedExposureLimitCopy =
    'Finish or leave another funded race before joining this one.';

/// Maps the additive funded-exposure contract without making an older backend
/// a client requirement. Unknown and uncoded errors retain their established
/// server copy.
String fundedExposureErrorCopy(ApiException error) {
  if (error.code == kFundedExposureLimitCode) {
    return kFundedExposureLimitCopy;
  }
  final message = error.message.trim();
  return message.isNotEmpty
      ? message
      : 'Something went wrong. Please try again.';
}
