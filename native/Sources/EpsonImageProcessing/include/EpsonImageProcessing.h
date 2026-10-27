#include <stdbool.h>
// Image processing only. This function never opens, arms or actuates a scanner.
int EDCorrectJPEG(const char *input, const char *output, bool rotate, unsigned int *orientation);
