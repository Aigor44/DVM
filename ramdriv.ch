/*
 * Very simple storage functions which make a block of RAM accessable
 * with file system like functions.
 */
Ushort
	RDfsec[RDFILES],	// File first sector
	RDcsec[RDFILES],	// "" current sector
	RDcoff[RDFILES],	// "" current offset
	RDeoff[RDFILES];	// "" end offset
Uchar
	*RDdrive;			// Allocated storage block

#define	RDERROR	0xFFFF

#define	RDebug(a)		//Pr a;
#define	RDckfile(a)		// Not necessary as DVM checks

// Get sector link
Ushort RDgetLink(Ushort s)
{
	Ulong p;
	p = s << 8;
	return (RDdrive[p+255] << 8) | RDdrive[p+254];
}

// Set sector link
void RDsetLink(Ushort s, Ushort v)
{
	Ulong p;
	p = s << 8;
	RDdrive[p+255] = v >> 8;
	RDdrive[p+254] = v;
}

// Allocate & initialize RAM disk
Ushort RDinit(Ulong s)
{
	if(RDdrive) {
		free(RDdrive);
		RDdrive = 0; }
	memset(RDfsec, 0, sizeof(RDfsec));
	memset(RDcsec, 0, sizeof(RDcsec));
	memset(RDcoff, 0, sizeof(RDcoff));
	memset(RDeoff, 0, sizeof(RDeoff));
	if(s) {
		if(s > (256*8)) {
re:			return RDERROR; }
		if(!(RDdrive = (Uchar*)malloc(s * 256)))
			goto re;
		memset(RDdrive, 0, 256);
		RDdrive[0] = 1; }
	return 0;
}

// Allocate a sector
Ushort RDalloc(void)
{
	Ushort i, s;
	Uchar c, d;
	for(i=s=0; i < 256; ++i) {
		if((c = RDdrive[i]) != 0xFF)
			goto a1;
		s += 8; }
	return 0;
a1:	d = 0x01;
	while(c & d) {
		d <<= 1;
		++s; }
	RDdrive[i] = c | d;
	RDsetLink(s, 0);
	return s;
}

// Release a chain of sectors
void RDrelChain(Ushort s)
{
	Ushort s1;
	Uchar m;
	while(s1 = s) {
		s = RDgetLink(s1);
		RDsetLink(s1, 0);
		m = 1 << (s1 & 7);
		s1 >>= 3;
		RDdrive[s1] &= ~m; }
}

// Open a file
Ushort RDopen(Ushort f, Ushort w)
{
	Ushort s;
	RDckfile(f);
	if(w) w=0x8000;
	if(RDcsec[f]) {			// Already open
		RDebug(("?f%uOAO", f))
rz:		return 0; }
	if(!(s = RDfsec[f])) {	// Erased
		if(!w) {
			RDebug(("?f%uONW", f))
			goto rz; }
		if(!(RDfsec[f] = s = RDalloc())) {
			RDebug(("?RDfull"))
			goto rz; }
		RDsetLink(s, 0); }
	RDcsec[f] = s;
	if(RDcoff[f] = w) {		// Open write
		RDrelChain(RDgetLink(s));
		RDsetLink(s, 0); }
	return f+1;
}

// Close an open file
Ushort RDclose(Ushort f)
{
	Ulong s;
	Ushort i;
	RDckfile(f);
	if(!(s = RDcsec[f])) {				// !open
		RDebug(("?f%uC!O", f))
		return RDERROR; }
	if((i = RDcoff[f]) & 0x8000) {		// open write
		i &= 0x7FFF;
		RDeoff[f] = i;
		RDrelChain(RDgetLink(s));
		RDsetLink(s, 0); }
	RDcsec[f] = RDcoff[f] = 0;
	return 0;
}

// Erase a file
Ushort RDerase(Ushort f)
{
	Ushort s;
	RDckfile(f);
	if(RDcsec[f]) {			// Open
		RDebug(("?f%uEO", f))
re:		return RDERROR; }
	if(!(s = RDfsec[f])) {	// Already erased
		RDebug(("?f%uEE", f);)
		goto re; }
	RDrelChain(s);
	RDfsec[f] = RDcsec[f] = RDcoff[f] = 0;
	return 0;
}

// Rewind an open file
Ushort RDrewind(Ushort f)
{
	RDckfile(f);
	if(!RDcsec[f]) {			// !open
		RDebug(("?f%uR!O", f))
re:		return RDERROR; }
	if(RDcoff[f] & 0x8000) {	// open write
		RDebug(("?f%uRW", f))
		goto re; }
	RDcsec[f] = RDfsec[f];
	RDcoff[f] = 0;
	return 0;
}

// Write character to open file
Ushort RDputc(Uchar c, Ushort f)
{
	Ulong s;
	Ushort i, s1;
	RDckfile(f);
	if(!(s = s1 = RDcsec[f])) {		// !open
		RDebug(("?f%uPNO", f))
re:		return RDERROR; }
	i = RDcoff[f] ^ 0x8000;
	if(i & 0x8000) {				// !write
		RDebug(("?f%uPOR", f))
		goto re; }
	if(i >= 254) {					// At EOB
		if(!(s = RDalloc())) {		// RDfull
			RDebug(("?f%u!A", f))
			goto re; }
		RDsetLink(s1, s);
		RDcsec[f] = s;
		i = 0; }
	RDdrive[(s << 8) + i] = c;
	RDcoff[f] = (i+1) | 0x8000;
	return c;
}

// Get char from open file
Ushort RDgetc(Ushort f)
{
	Ulong s;
	Ushort i, s1;
	RDckfile(f);
	if(!(s = RDcsec[f])) {			// !open
		RDebug(("?f%uGNO", f))
re:		return RDERROR; }
	if((i = RDcoff[f]) & 0x8000) {	// openW
		RDebug(("?f%uGNR", f))
		goto re; }
	if(!(s1 = RDgetLink(s))) {		// EOF
		if(i >= RDeoff[f]) {
			RDebug(("?f%uGE1", f))
			goto re; } }
	if(i >= 254) {					// EOB
		if(!s1) {
			RDebug(("?f%uGE2", f))
			goto re; }
		RDcsec[f] = s = s1;
		i = 0; }
	RDcoff[f] = i+1;
	return RDdrive[(s << 8) +i];
}
