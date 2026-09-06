// Only these backend-authored messages may reach the Copy panel verbatim.
// Keep each category in sync with its mapping in services/payor_copy.py.
const COPY_BLOCK_MESSAGES = new Set([
  "A valid copy request and audit identity are required.",
  "Choose a destination payor different from the source.",
  "Source and destination Line of Business must match.",
  "The billing form must match the source for every destination context.",
  "Ambiguous or unsupported claim settings require review before copying.",
  "The destination cannot resolve the same complete configuration as the source. Review payor type and template compatibility.",
  "Copy verification failed. No changes were saved.",
  "Configuration is being changed by another session. Try Preview again shortly.",
]);

const COPY_SOURCE_MESSAGES = new Set([
  "A valid source payor, optional plan, and audit identity are required.",
  "The source billing form is not supported for copying.",
  "The source payor or plan has missing, ambiguous, or unsupported claim settings. Review the source before copying.",
  "The source configuration could not be resolved. Check the selected payor and plan ownership.",
  "The source configuration is ambiguous or has a missing entry date. Review the source before copying.",
  "The source inherits invalid claim settings. Correct its template or billing-form settings before copying.",
  "The source payor was not found.",
  "Save Line of Business for the source payor before copying.",
]);

export const safeCopyErrorMessage = (category: string, message: string): string | null => {
  if (category === "copy_blocked") {
    return COPY_BLOCK_MESSAGES.has(message) ? message
      : "The settings cannot be copied to this destination. Review the source and destination configurations.";
  }
  if (category === "copy_source_blocked") {
    return COPY_SOURCE_MESSAGES.has(message) ? message
      : "The source configuration must be corrected before copying. Review the selected payor and plan.";
  }
  return null;
};
