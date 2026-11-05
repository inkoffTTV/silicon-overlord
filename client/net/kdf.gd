extends RefCounted
## Password -> derived key for accounts (docs/ACCOUNTS.md). The raw password never leaves this PC:
##   key = PBKDF2-HMAC-SHA256(password, "silicon-overlord:" + lowercase(username), ITERATIONS, 32 bytes) as hex
## The server stores only scrypt(key, random salt). Must match server/sos/accounts.py (KDF_ID) and the
## Python check in server/tests/test_accounts.py (derive()).
## ~0.35 s for 100k iterations in GDScript on a desktop CPU; Net runs it on a thread so the UI keeps drawing.

const ITERATIONS := 100000
const KDF_ID := "pbkdf2-sha256-100000"
const SALT_PREFIX := "silicon-overlord:"

static func derive(username: String, password: String, iterations: int = ITERATIONS) -> String:
	var salt := (SALT_PREFIX + username.to_lower()).to_utf8_buffer()
	return pbkdf2_sha256(password.to_utf8_buffer(), salt, iterations).hex_encode()

## PBKDF2-HMAC-SHA256, one 32-byte block (HMAC built from two HashingContexts with precomputed pads).
static func pbkdf2_sha256(pw: PackedByteArray, salt: PackedByteArray, iterations: int) -> PackedByteArray:
	var k := pw
	var h := HashingContext.new()
	if k.size() > 64:
		h.start(HashingContext.HASH_SHA256)
		h.update(k)
		k = h.finish()
	k = k.duplicate()
	k.resize(64)
	var ipad := PackedByteArray()
	var opad := PackedByteArray()
	ipad.resize(64)
	opad.resize(64)
	for i in 64:
		ipad[i] = k[i] ^ 0x36
		opad[i] = k[i] ^ 0x5c
	var s := salt.duplicate()
	s.append_array(PackedByteArray([0, 0, 0, 1]))
	h.start(HashingContext.HASH_SHA256)
	h.update(ipad)
	h.update(s)
	var inner := h.finish()
	h.start(HashingContext.HASH_SHA256)
	h.update(opad)
	h.update(inner)
	var u := h.finish()
	# running XOR kept as four 64-bit words
	var t0 := u.decode_s64(0)
	var t1 := u.decode_s64(8)
	var t2 := u.decode_s64(16)
	var t3 := u.decode_s64(24)
	for _i in range(1, iterations):
		h.start(HashingContext.HASH_SHA256)
		h.update(ipad)
		h.update(u)
		inner = h.finish()
		h.start(HashingContext.HASH_SHA256)
		h.update(opad)
		h.update(inner)
		u = h.finish()
		t0 ^= u.decode_s64(0)
		t1 ^= u.decode_s64(8)
		t2 ^= u.decode_s64(16)
		t3 ^= u.decode_s64(24)
	var out := PackedByteArray()
	out.resize(32)
	out.encode_s64(0, t0)
	out.encode_s64(8, t1)
	out.encode_s64(16, t2)
	out.encode_s64(24, t3)
	return out
