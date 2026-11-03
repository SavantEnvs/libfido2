/* Known-answer probe of libfido2's public API; prints one line per check (see mayhem/test.sh). */
#include <stdio.h>
#include <string.h>

#include "fido.h"

static void
hex(const char *label, const unsigned char *p, size_t n)
{
	printf("%s=", label);
	for (size_t i = 0; p && i < n; i++)
		printf("%02x", p[i]);
	printf("\n");
}

int
main(void)
{
	fido_assert_t *a;
	fido_cred_t *c;
	fido_cbor_info_t *ci;

	fido_init(0);

	/* clientdata is hashed with SHA-256: FIPS 180-2 known answers */
	if ((a = fido_assert_new()) == NULL)
		return 1;
	printf("set_abc=%d\n", fido_assert_set_clientdata(a,
	    (const unsigned char *)"abc", 3));
	hex("assert_cdh_abc", fido_assert_clientdata_hash_ptr(a),
	    fido_assert_clientdata_hash_len(a));
	fido_assert_free(&a);

	if ((c = fido_cred_new()) == NULL)
		return 1;
	printf("set_msg=%d\n", fido_cred_set_clientdata(c,
	    (const unsigned char *)"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq", 56));
	hex("cred_cdh_msg", fido_cred_clientdata_hash_ptr(c),
	    fido_cred_clientdata_hash_len(c));
	/* a second clientdata on the same credential is rejected */
	printf("set_twice=%d\n", fido_cred_set_clientdata(c,
	    (const unsigned char *)"abc", 3));
	fido_cred_free(&c);

	if ((ci = fido_cbor_info_new()) == NULL)
		return 1;
	printf("info_versions=%zu\n", fido_cbor_info_versions_len(ci));
	fido_cbor_info_free(&ci);

	printf("strerr=%s\n", fido_strerr(FIDO_ERR_INVALID_ARGUMENT));
	printf("kat_done=1\n");
	return 0;
}
