#include <stddef.h>

/* The run-once driver has no libFuzzer runtime; mutation is never requested, so identity is correct. */
size_t
LLVMFuzzerMutate(unsigned char *data, size_t size, size_t max_size)
{
	(void)data;
	(void)max_size;
	return size;
}
