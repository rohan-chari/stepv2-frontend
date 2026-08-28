import '../services/backend_api_service.dart';

const String kFundedExposureLimitCode = 'FUNDED_EXPOSURE_LIMIT';
const String kActiveCompetitionLimitCode = 'ACTIVE_COMPETITION_LIMIT';
const String kActiveCompetitionLimitFallbackCopy =
    'You’ve reached the active competition limit. Finish or leave an active competition, then try again.';

bool isActiveCompetitionLimitError(ApiException error) =>
    error.code == kActiveCompetitionLimitCode ||
    error.code == kFundedExposureLimitCode;

/// Maps the additive funded-exposure contract without making an older backend
/// a client requirement. Unknown and uncoded errors retain their established
/// server copy.
String fundedExposureErrorCopy(ApiException error) {
  if (error.code == kActiveCompetitionLimitCode) {
    final rawLimit = error.details?['limit'];
    if (rawLimit is int && rawLimit > 0) {
      return 'You can have up to $rawLimit active competitions at a time.';
    }
    return kActiveCompetitionLimitFallbackCopy;
  }
  if (error.code == kFundedExposureLimitCode) {
    // A new client can encounter this during a backend rolling deploy. Avoid
    // resurrecting the misleading funded-only wording in that mixed-version
    // window because the client cannot prove which legacy guard emitted it.
    return kActiveCompetitionLimitFallbackCopy;
  }
  final message = error.message.trim();
  return message.isNotEmpty
      ? message
      : 'Something went wrong. Please try again.';
}
