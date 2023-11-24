#define	OSFILES	10		// Max number of open files
#define	RDFILES	10		// "" of RamDisk files
#define	FARSEG	10		// Max numbe of far segnebts

#define	UM_TEMP		0
#define	UM_LONGREG	2
#define	UM_HEAP		6

#define	SIZ		2	// RPC: Size of HANDLE prefix
#define	RPS		10	// RPC: #RProcS

FILE
	*OSfiles[OSFILES];
int
	Hr,				// RPC read handle
	Hw,				// RPC write handle
	HrL[RPS],		// RPC rh list
	HwL[RPS];		// RPC wh list
Ushort
	UniMem,
	CapFile,
	FarSiz[FARSEG];
Uchar
	*FarSeg[FARSEG],
	RDletter;

#include "ramdriv.ch"

int __stdcall Beep(unsigned, unsigned);
void LIBexit(void);

// RPC
#define _P_NOWAIT	1
#define	_O_BINARY	0x8000
int  _pipe(int *, unsigned int, int);
int  _read(int, void *, unsigned int);
int  _write(int, const void *, unsigned int);
int  _close(int);

/*
 * Various support functions
 */
void FmtArg(void)				// Setup FMTarg
{
	FMTarg = (ACC*2)+SP-2;
}
Ulong Lget(Ushort i)			// Get a LONG value
{
	return (MemData[i+3]<<24)|(MemData[i+2]<<16)|(MemData[i+1]<<8)|MemData[i];
}
void Lput(Ushort i, Ulong v)	// Put a LONG value
{
	MemData[i]		= v;
	MemData[i+1]	= v >> 8;
	MemData[i+2]	= v >> 16;
	MemData[i+3]	= v >> 24;
}
Ulong AtoV(Uchar *p, Ushort r)
{
	Ulong v;
	Uchar c, m;
	v = 0;
	if((m = *p) == '-') ++p;
	for(;;) {
		c = *p;
		if((c >= '0') && (c <= '9'))		c -= '0';
		else if((c >= 'A') && (c <= 'F'))	c -= ('A'-10);
		else if((c >= 'a') && (c <= 'f'))	c -= ('a'-10);
		else		break;
		if(c >= r)	break;
		v = (v*r) + c;
		++p; }
	if(m == '-')	v = -v;
	return v;
}
Ushort VtoA(Ulong v, Ushort a, Ushort r)
{
	Ushort i, j;	Uchar c, s[10];
	if(r & 0x8000) {
		r = (-r) & 0x7FFF;
		if(v & 0x80000000) {
			v = -v;
			MemData[a++] = '-'; } }
	i = 0; do {
		s[i++] = v % r; }
	while(v /= r);
	j = i;
	while(i) {
		if((c = s[--i] + '0') > '9')
			c += ('A'-10);
		MemData[a++] = c; }
	MemData[a] = 0;
	return j;
}
Ushort RDmem2(Ushort a)
{
	return (MemData[a+1] << 8) | MemData[a];
}
void WRmem2(Ushort a, Ushort v)
{
	MemData[a]		= v;
	MemData[a+1]	= v >> 8;
}
void Free(Ushort h)
{
	Ushort a, b, ea, es;
	MemData[h -= 3] = 1;
	a = UniMem + UM_HEAP;
	ea = es = 0;
a1:	switch(MemData[a]) {
	case 1 :	// Released
a2:		if(!es) ea = a;
		b = RDmem2(a+1) + 3;
		es += b;
		goto a3;
	default:	// Allocated
		if(a == h) {
			MemData[a] = 1;
			goto a2; }
		if(es) {
			WRmem2(ea+1, es-3);
			es = 0; }
		b = RDmem2(a+1) + 3;
a3:		a += b;
		goto a1;
	case 0 : ; }
	if(es)
		MemData[ea] = 0;
}
Ushort Malloc(Ushort s)
{
	Ushort a, sa, ea, bs, s1;
	sa = a = UniMem + UM_HEAP;
	s1 = s + 3;	// Size with overhead
a1:	if((ea = a + s1) < sa) {
		return 0; }
	switch(MemData[a]) {
	default:	// Used
		bs = RDmem2(a+1);
a2:		a += (bs+3);
		goto a1;
	case 0 :	// Unalocated
a3:		WRmem2(a+1, s);
a4:		MemData[a] = 2;
		return a+3;
	case 1:		// Released
		bs = RDmem2(a+1);
		if(bs < s)	goto a2;	// Not enough
		if(bs > s1) {
			MemData[ea] = 1;
			WRmem2(ea+1, bs-s1);
			goto a3; }
		goto a4; }
}
Ushort _scan_(Uchar *input)
{
	Ushort op, count, value, value1, base;
	Uchar *format, *savinp, chr, mflag, cflag;

	format = RDarg2()+MemData;
	count = 0;

	while(chr = *format++) {
		if(isspace(chr))		/* whitespace */
			continue;
		savinp = input;
		while(isspace(*input))
			++input;
		if(chr != '%') {		/* Non-format character */
			if(*input == chr)
				++input;
			continue; }
		FMTarg -= 2;
		op = RDarg2();
		cflag = mflag = base = value = value1 = 0;
		while(isdigit(chr = *format++))		/* get width if any */
			value = (value * 10) + (chr - '0');
		switch(chr) {
			case 'c' :				/* character input */
				input = savinp;
				value1 = value ? value : 1;
				while(value1-- && (MemData[op] = *input)) {
					++op;
					++input;
					cflag = 1; }
				if(value)
					goto a1;
				break;
			case 's' :				/* string input */
				do {
					if((!(chr = *input)) || isspace(chr))
						break;
					MemData[op++] = chr;
					++input;
					cflag = 1; }
				while(--value);
a1:				MemData[op] = 0;
				break;
			case 'd' :				/* signed number */
				if(*input == '-') {
					++input;
					mflag = -1; }
			case 'u' :				/* unsigned number */
				base = 10;
				break;
			case 'b' :				/* Binary number */
				base = 2;
				break;
			case 'o' :				/* Octal number */
				base = 8;
				break;
			case 'x' :				/* Hexidecimal number */
				base = 16;
				break;
			case '%' :				/* Doubled percent sign */
				if(*input == '%')
					++input;
				break;
			default:				/* Illegal type character */
				return 0; }

		if(base) {				/* Number conversion required */
			do {
				if(isdigit(chr = *input))
					chr -= '0';
				else if(chr >= 'a')
					chr -= ('a' - 10);
				else if(chr >= 'A')
					chr -= ('A' - 10);
				else
					break;
				if(chr >= base)
					break;
				value1 = (value1 * base) + chr;
				cflag = 1;
				++input; }
			while(--value);
			WRmem2(op, (mflag) ? -value1 : value1); }
		count += cflag; }
	return count;
}
void GetTime(Ushort *h, Ushort *m, Ushort *l, Uchar ty)
{
	struct tm t;
	_getsystime(&t);
	if(ty) {
		*h = t.tm_hour;
		*m = t.tm_min;
		*l = t.tm_sec; }
	else {
		*h = t.tm_mday;
		*m = t.tm_mon+1;
		*l = t.tm_year+1900; }
}

/*
 * Library functions
 */
Ushort XFname(Uchar *p)
{
	Ushort f;
//Pr("Xfname('%s', '%c')\n", p, RDletter);
	if((*p != RDletter) || (p[1] != ':')) {
rn:		return 255; }
	p += 2;
	if(*p == '\\') ++p;
	if((f = *p - '0') >= RDFILES)
		goto rn;
	switch(p[1]) {
	case'.':	if(!p[2])	break;
	default:	goto rn;
	case 0 : ; }
	return f;
}
	
void Xopen(Ushort fe, Ushort fo)
{
	Ushort f, w;
	Uchar c, *p, op, opt[16];

	ACC = f = w = op = opt[0] = 0;
	p = fe+MemData;
a1:	switch(c = *p++) {
	case 'a':
	case 'w':	w = 0x8000;
	case 'r':	*opt = c;		goto a1;
	default :	opt[++f] = c;	goto a1;
	case 'v':	op|=1;	goto a1;
	case 'q':	op|=2;	goto a1;
	case 'h': 	op|=4;	goto a1;
	case 0	:	opt[f+1] = 0; }

	if((f = XFname(p = fo+MemData)) & 0xF0) {	// OSfile
		for(f=0; f < OSFILES; ++f) {
			if(!OSfiles[f]) {
				if(OSfiles[f] = fopen(p, opt)) {
					ACC = f + 1; }
				goto e1; } }
		goto e1; }
	if(RDopen(f, w))
		ACC = f+(OSFILES+1);
e1:	if(!ACC) {	// Open failed
		if(op & 1)	Pr("%s: open failed!\n", p);
		if(op & 4)	exit(-1);
		if(op & 2)	{
			ACC = 255;
			LIBexit(); } }
}

void LIBfopen(void)
{
	Xopen(Arg0(), Arg1());
}

Uchar Xclose(Ushort f)
{
	if(CapFile && (f == CapFile))
		goto rz;
	if(--f < OSFILES) {
		if(f > 2) {
			if(OSfiles[f] && fclose(OSfiles[f]))
				goto re;
			OSfiles[f] = 0; }
rz:		return 0; }
	if((f -= OSFILES) < RDFILES) {
		if(!RDclose(f))
			goto rz; }
re:	return 255;
}
void LIBfclose(void)
{
	ACC = Xclose(Arg0());
}
void LIBfreopen(void)
{
	Ushort f;
	ACC = 0;
	if((f = Arg3()-1) < OSFILES) {
		Xclose(f+1);
		Xopen(Arg0(), Arg2());
		if(ACC) {
			OSfiles[f] = OSfiles[ACC-1]; 
			OSfiles[ACC-1] = 0;
			ACC = f+1; } }
}
void LIBrewind(void)
{
	Ushort f;
	if((f = Arg0()-1) < OSFILES) {
		rewind(OSfiles[f]);
		return; }
	if((f -= OSFILES) < RDFILES)
		RDrewind(f);
}
void LIBfseek(void)
{
	Ulong p;	Ushort f;
	p = (Arg2() << 16) | Arg1();
	ACC = 255;
	if((f = Arg3()-1) < OSFILES)
		ACC = fseek(OSfiles[f], p, Arg0());
	return;
}
void LIBftell(void)
{
	Ulong p;	Ushort f;
	ACC = 0;
	if((f = Arg2()-1) < OSFILES) {
		p = ftell(OSfiles[f]);
		MemData[f=Arg1()] = p >> 16;
		MemData[f+1] = p >> 24;
		MemData[f=Arg0()] = p;
		MemData[f+1] = p >> 8;
		ACC = 0; }
}
void LIBfflush(void)
{
	Ushort f;
	ACC = 255;
	if((f = Arg0()-1) < OSFILES)
		ACC = fflush(OSfiles[f]);
}
Ushort XFput(Uchar *p, Ushort l, Ushort f)
{
	FILE *fp;
	Ushort r;
	r = 0;
	if(--f < OSFILES) {
		if(fp = OSfiles[f])
			r = Fput(p, l, fp);
		return r; }
	if((f-=OSFILES) < RDFILES) {
		while(r < l) {
			if(RDputc(*p++, f) & 0xFF00)
				break;
			++r; } }
	return r;
}
void LIBfput(void)
{
	ACC = XFput(Arg2()+MemData, Arg1(), Arg0());
}
void LIBfwrite(void)
{
	Ushort c, l, f;
	Uchar *p;
	p = Arg3()+MemData;
	l = Arg2();
	c = Arg1();
	f = Arg0();
	for(ACC = 0; ACC < c; ++ACC) {
		if(!XFput(p, l, f))
			break;
		p += l; }
}
Ushort XFget(Uchar *p, Ushort l, Ushort f)
{
	FILE *fp;
	Ushort r, c;
	r = 0;
	if(--f < OSFILES) {
		if(fp = OSfiles[f])
			r = Fget(p, l, fp);
		return r; }
	if((f-=OSFILES) < RDFILES) {
		while(r < l) {
			if((c = RDgetc(f)) & 0xFF00)
				break;
			*p++ = c;
			++r; } }
	return r;
}
void LIBfget(void)
{
	ACC = XFget(Arg2()+MemData, Arg1(), Arg0());
}
void LIBfread(void)
{
	Ushort c, l, f;
	Uchar *p;
	p = Arg3()+MemData;
	l = Arg2();
	c = Arg1();
	f = Arg0();
	for(ACC = 0; ACC < c; ++ACC) {
		if(!XFget(p, l, f))
			break;
		p += l; }
}
void Xputc(Uchar c, Ushort f)
{
	FILE *fp;
	ACC = -1;
	if(--f < OSFILES) {
		if((CapFile > 2) && (f < 3))
			Xputc(c, CapFile);
		if(fp = OSfiles[f])
			putc(ACC = c, fp);
		return; }
	if((f -= OSFILES) < RDFILES)
		ACC = RDputc(c, f);
}
void LIBputc(void)
{
	Xputc(Arg1(), Arg0());
}
void LIBputchar(void)
{
	Xputc(Arg0(), 2);	// stdout
}
Ushort XFputs(Uchar *p, Ushort f)	// 2=stdout 3=stderr
{
	FILE *fp;
	Uchar c;
	if(--f < OSFILES) {
		if((CapFile > 2) && (f < 3))
			XFputs(p, CapFile); 
		if(fp = OSfiles[f])
			return fputs(p, fp);
		goto rz; }
	if((f -= OSFILES) < RDFILES) {
		while(*p) {
			if(RDputc(c = *p++, f) & 0xFF00)
				goto rz; }
		return c; }
rz:	return -1;
}
void LIBfputs(void)
{
	ACC = XFputs(Arg1()+MemData, Arg0());
}
LIBputs(void)
{
	ACC = XFputs(Arg0()+MemData, 2);
}
void LIBgetc(void)
{
	FILE *fp;	Ushort f;
	ACC = -1;
	if((f = Arg0()-1) < OSFILES) {
		if(fp = OSfiles[f])
			ACC = getc(fp);
		return; }
	if((f -= OSFILES) < RDFILES)
		ACC = RDgetc(f);
}
void LIBgetchar(void)
{
	ACC = getc(stdin);
}
Ushort XFgets(Uchar *p, Ushort l, Ushort f)	// 1=STDIN
{
	FILE *fp;	Ushort i, j;
	i = 0;
	if(--f < OSFILES) {
		if(fp = OSfiles[f]) {
			if(fgets(p, l, fp))
				goto e1; }
		goto rz; }
	if((f -= OSFILES) < RDFILES) {
		while(i < l) {
			if((j = RDgetc(f)) & 0xFF00)
				break;
			if(j == '\n')
				break;
			p[i++] = j; }
		p[i] = 0;
		if(i || !(j & 0xFF00))
			goto e2; }
rz:	return p[i] = 0;
e1:	switch(p[i]) {
	default:	++i;		goto e1;
	case'\n':	p[i] = 0;
	case 0:	; }
e2:	return 255;
}
void LIBfgets(void)
{
	ACC = Arg2();
//Pr("[G%x", ACC);
	if(!XFgets(ACC+MemData, Arg1(), Arg0())) {
		ACC = 0; }
}
void LIBgets(void)
{
	ACC = Arg1();
	if(!XFgets(ACC+MemData, Arg0(), 1))
		ACC = 0;
}
void LIB_format_(void)
{
	FMTarg = Arg1()-2;
	ACC =_Format_(Arg0()+MemData, 255);
}
void LIBprintf(void)
{
	FmtArg();
	ACC = _Format_(Buffer, 255);
//?	fputs(Buffer, stdout);
	XFputs(Buffer, 2);	//stdout
}
void LIBfprintf(void)
{
	Ushort f;
	FmtArg();	f = RDarg2();	FMTarg -= 2;
	ACC = _Format_(Buffer, 255);
	XFputs(Buffer, f);
}
void LIBsprintf(void)
{
	Ushort i;
	FmtArg();	i = RDarg2();	FMTarg -= 2;
	ACC = _Format_(i+MemData, 255);
}
void LIBscanf(void)
{
	FmtArg();
//?	fgets(Buffer, sizeof(Buffer)-1, stdin);
	ACC = -1;
	if(XFgets(Buffer, sizeof(Buffer), 1))
		ACC = _scan_(Buffer);
}
void LIBfscanf(void)
{
	Ushort f;
	FmtArg();	f = RDarg2();	FMTarg -= 2;
	ACC = -1;
	if(XFgets(Buffer, sizeof(Buffer)-1, f))
		ACC = _scan_(Buffer);
}
void LIBsscanf(void)
{
	Ushort i;
	FmtArg();	i = RDarg2();	FMTarg -= 2;
	ACC = _scan_(MemData + i);
}
void LIBdelete(void)
{
	Ushort f;
	Uchar *p;
	if((f = XFname(p = Arg0()+MemData)) & 0xF0) {
		ACC = remove(Arg0()+MemData);
		return; }
	RDerase(f);
}
void LIBrename(void)
{
	ACC = rename(Arg0()+MemData, Arg1()+MemData);
}
void LIBatoi(void)
{
	ACC = AtoV(Arg0()+MemData, 10);
}
void LIBatox(void)
{
	ACC = AtoV(Arg0()+MemData, 16);
}
void LIBitoa(void)
{
	Ulong v;
	Ushort r;
	v = Arg2();
	r = Arg0();
	if(v & r & 0x8000)
		v |= 0xFFFF0000;
	ACC = VtoA(v, Arg1(), r);
}
Ushort isfunc(Uchar l, Uchar h)
{
	Ushort c;
	c = Arg0();
	return ((c >= l) && (c <= h));
}
void LIBisascii(void)	{	ACC = isfunc(0x00, 0x7F);	}
void LIBisdigit(void)	{	ACC = isfunc('0', '9');		}
void LIBislower(void)	{	ACC = isfunc('a', 'z');		}
void LIBisupper(void)	{	ACC = isfunc('A', 'Z');		}
void LIBisgraph(void)	{	ACC = isfunc(0x21, 0x7E);	}
void LIBisalpha(void)	{	ACC = isfunc('a', 'z') | isfunc('A', 'Z');	}
void LIBisalnum(void)	{	ACC = isfunc('a', 'z') | isfunc('A', 'Z')
	| isfunc('0', '9'); }
void LIBisxdigit(void)	{	ACC = isfunc('a', 'f') | isfunc('A', 'F')
	| isfunc('0', '9'); }
void LIBisspace(void)
{
	switch(Arg0()) {
	case '\t':
	case '\n':
	case ' ' :
		ACC = 1;
		return; }
	ACC = 0;
}
void LIBisprint(void)	{	ACC = isfunc(' ', 0x7E);		}
void LIBiscntrl(void)
{
	Ushort c;
	c = Arg0();
	ACC = (c < ' ') || (c == 0x7F);
}
void LIBispunct(void)
{
	Ushort a;
	LIBisalnum();	a = ACC;
	LIBisgraph();
	if(a) ACC = 0;
}

void LIBstrcpy(void)
{
	strcpy((ACC = Arg1())+MemData, Arg0()+MemData);
}
void LIBstpcpy(void)
{
	Ushort d, s;
	d = Arg1();	s = Arg2();
	while(MemData[d] = MemData[s++])
		++d;
	ACC = d;
}

void LIBstrncpy(void)
{
	Ushort d, s, l;
	ACC = d = Arg2();
	s = Arg1();
	l = Arg0();
	while(l) {
		--l;
		if(MemData[d++] = MemData[s])
			++s; }
}
void LIBstrcat(void)
{
	strcat(Arg1()+MemData, Arg0()+MemData);
	ACC = Arg1();
}
void LIBstrcmp(void)
{
	ACC = strcmp(Arg1()+MemData, Arg0()+MemData);
}
Uchar Strbeg(Uchar *s1, Uchar *s2)
{
	while(*s2) {
		if(*s1++ != *s2++)
			return 0; }
	return 1;
}	
void LIBstrbeg(void)
{
	ACC = Strbeg(MemData+Arg1(), MemData+Arg0());
}
void LIBstrlen(void)
{
	ACC = strlen(Arg0()+MemData);
}
void LIBstrchr(void)
{
	Uchar c, d;
	ACC = Arg1(); c = Arg0();
	do {
		if((d = MemData[ACC]) == c)
			return;
		++ACC; }
	while(d);
	ACC = 0;
}
void LIBmemset(void)
{
	Ushort d, l;
	Uchar v;
	ACC = d = Arg2();
	v = Arg1();
	l = Arg0();
	while(l) {
		MemData[d++] = v;
		--l; }
}
void LIBmemcpy(void)
{
	Ushort d, s, l;
	ACC = d = Arg2();
	s = Arg1();
	l = Arg0();
	if(s >= d) {
		while(l) {
			MemData[d++] = MemData[s++];
			--l; }
		return; }
	s += l;
	d += l;
	while(l) {
		MemData[--d] = MemData[--s];
		--l; }
}
void LIBmalloc(void)
{
	ACC = Malloc(Arg0());
}
void LIBcalloc(void)
{
	Ushort s;
	ACC = Malloc(s = Arg0() * Arg1());
	memset(MemData + ACC, 0, s);
}
void LIBfree(void)
{
	Free(Arg0());
}
void LIBrealloc(void)
{
	Ushort o, s, i;
	Free(o = Arg0());
	ACC = Malloc(s=Arg1());
	if(o > ACC) {
		for(i=0; i < s; ++i)
			MemData[ACC+i] = MemData[o+i]; }
	else if(o < ACC) {
		if(i = s) {
			do {
				--i;
				MemData[ACC+i] = MemData[o+i]; }
			while(i); } }
}
void LIBcoreleft(void)
{
	Ushort a;
	a = UniMem + UM_HEAP;
	while(MemData[a])
		a += (RDmem2(a+1) + 3);
	if((a+=100) > SP)
		a = SP;
	ACC = SP - a;
}
void LIBlongset(void)
{
	Lput(Arg1(), ACC = Arg0());
}
void LIBlongcpy(void)
{
	Lput(Arg1(), Lget(Arg0()));
}
void LIBlongtst(void)
{
	ACC = Lget(Arg0()) ? 1 : 0;
}
void LIBlongcmp(void)
{
	Ulong a, b;
	a = Lget(Arg1());	b = Lget(Arg0());
	if(a < b)		ACC = -1;
	else if(a > b)	ACC = 1;
	else			ACC = 0;
}
void LIBlongadd(void)
{
	Ulong a, b, r;
	Ushort d;
	a = Lget(d=Arg1());
	b = Lget(Arg0());
	Lput(d, r = a + b);
	ACC = r < a;
}
void LIBlongsub(void)
{
	Ulong a, b;
	Ushort d;
	a = Lget(d=Arg1());
	b = Lget(Arg0());
	ACC = a < b;
	Lput(d, a - b);
}
void LIBlongmul(void)
{
	Ulong v;
	Ushort d;	d = Arg1();
	Lput(d, v = Lget(d) * Lget(Arg0()));
	Lput(UniMem+UM_LONGREG, v);
}
void LIBlongdiv(void)
{
	Ulong v1, v2;
	Ushort d;	d = Arg1();
	v1 = Lget(d);
	v2 = Lget(Arg0()); 
	Lput(d, v1 / v2);
	Lput(UniMem+UM_LONGREG, v1 % v2);
}
void LIBlongshl(void)
{
	Ulong v;	Ushort d;
	v = Lget(d = Arg0());
	Lput(d, v << 1);
	ACC = (v & 0x80000000) ? 1 : 0;
}
void LIBlongshr(void)
{
	Ulong v;	Ushort d;
	v = Lget(d = Arg0());
	Lput(d, v >> 1);
	ACC = v & 1;
}
void LIBltoa(void)
{
	VtoA(Lget(Arg2()), Arg1(), Arg0());
}
void LIBatol(void)
{
	Lput(Arg1(), AtoV(Arg2()+MemData, Arg0()));
}
void LIBmin(void)
{
	Sshort a, b;
	a = Arg1();
	b = Arg0();
	ACC = (a < b) ? a : b;
}
void LIBmax(void)
{
	Sshort a, b;
	a = Arg1();
	b = Arg0();
	ACC = (a > b) ? a : b;
}
void LIBabs(void)
{
	Ushort a;
	a = Arg0();
	ACC = (a & 0x8000) ? -a : a;
}
void LIBconcat(void)
{
	Ushort d, s;
	FmtArg();
	d = RDarg2();
	while(--ACC) {
		FMTarg -= 2;
		s = RDarg2();
		while(MemData[s])
			MemData[d++] = MemData[s++]; }
	MemData[d] = 0;
}
void LIBtoupper(void)
{
	ACC = toupper(Arg0());
}
void LIBtolower(void)
{
	ACC = tolower(Arg0());
}
void LIBstrupr(void)
{
	Ushort i;
	Uchar c;
	i = Arg0();
	while(c = MemData[i])
		MemData[i++] = toupper(c);
}
void LIBstrlwr(void)
{
	Ushort i;
	Uchar c;
	i = Arg0();
	while(c = MemData[i])
		MemData[i++] = tolower(c);
}
#define PRECESSION  (16>>1)
Ushort LIBsqrt(void)
{
	Ushort value, root, rootsquared, mask, masksquared, power, t;
	value = Arg0();
	root = rootsquared = 0;
	mask        = 1 <<  (PRECESSION-1);
	masksquared = 1 << ((PRECESSION-1) << 1);
	power = PRECESSION;
	do {
		if((t = (root<<power)+rootsquared+masksquared) <= value) {
			rootsquared = t;
			root |= mask; }
		mask >>= 1;
		masksquared >>= 2; }
	while(--power);

	rootsquared = root+1;
	ACC = ((value - (root*root)) < ((rootsquared*rootsquared)-value))
		? root : rootsquared;
}
void LIBsetjmp(void)
{
	Ushort a;
	a = Arg0();
	WRmem2(a, PC);	// Return address
	WRmem2(a+2, SP);		// Adjusted SP
	ACC = 0;
}
void LIBlongjmp(void)
{
	Ushort a;
	a = Arg1();
	ACC = Arg0();
	PC = RDmem2(a);
	SP = RDmem2(a+2);
}
void LIBget_date(void)
{
	GetTime(Arg2()+MemData, Arg1()+MemData, Arg0()+MemData, 0);
}
void LIBget_time(void)
{
	GetTime(Arg2()+MemData, Arg1()+MemData, Arg0()+MemData, 255);
}
void LIBgetenv(void)
{
	Uchar *p, *p1, *p2;
	p1 = Arg0()+MemData;
	if(p = getenv(p2 = Arg1()+MemData)) {
		strcpy(p1, p);
a1:		ACC = 1;
		return; }
	if(!strcmp(p2, "DVM")) {
		strcpy(p1, HomeDir);
		if(*p1) goto a1; }
	*p1 = ACC = 0;
}
void LIBdelay(void)
{
	sleep(Arg0());
}
void LIBbeep(void)
{
	Beep(Arg1(), Arg0());
}
// Get a character with special key translatio
void LIBkbget(void)
{
	ACC = Vgetc();
}
void LIBkbhit(void)
{
	ACC = kbhit();
}
// Test for character with special key translaction
void LIBkbtst(void)
{
	if(kbhit()) {
		ACC = Vgetc();
		return; }
	ACC = 0;
}
void LIBVgotoxy(void)
{
	Vgotoxy(Arg1(), Arg0());
}
#define	LIBVcleol	Vcleol
#define	LIBVcleos	Vcleos
#define	LIBVclscr	Vclscr
void LIBVcursor(void)
{
	Vcursor(Arg0());
}
void LIBVopen(void)
{
	ACC = Vopen(Arg0());
}
#define	LIBVclose	Vclose
void LIBVgetc(void)
{
	ACC = Vgetc();
}
void LIBVgetk(void)
{
	ACC = Vkey();
}
void LIBVgets(void)
{
	ACC = Vgets(Arg1()+MemData, Arg0());
}
void LIBVputc(void)
{
	Vputc(Arg0());
}
void LIBVputs(void)
{
	Vputs(Arg0()+MemData);
}
void LIBVprintf(void)
{
	FmtArg();
	ACC = _Format_(Buffer, 255);
	Vputs(Buffer);
}
void LIBVcolor(void)
{
	textattr(Arg0());
}
void LIBVFcolor(void)
{
	textcolor(Arg0());
}
void LIBVBcolor(void)
{
	textbackground(Arg0());
}
void LIBRDsetup(void)
{
	Ushort l, s;
	if(!(l = Arg1())) goto a1;
	if(!(s = Arg0())) {
a1:		l = s = 0; }
	RDletter = l;
	ACC = RDinit(s);
}
void LIBabort(void)
{
	fputs(Arg0()+MemData, stderr);
	ACC = 255;
	LIBexit();
}
void LIBsystem(void)
{
// SW_HIDE=0 SW_NORMAL=1 SW_MAXIMIZE=3 SW_MINIMIZE=6
//	ACC = _System(Arg1()+MemData, Arg0());
	ACC = system(Arg0()+MemData);
}
void STKargs(void)
{
	unsigned char buf[256];
	while(parse(buf))
		stack_string(buf);
}
void LIBexec(void)
{
	Uchar	*sMC, *sA0p, savjmp[20];
	Ushort	sSP, sPC, sMD, sLFS;

	sSP = SP;	sPC = PC;	sMC = MemCode;	sLFS = LibFunSiz;
	sMD = MemData - MemCode;
	sA0p = Arg0()+MemData;
	if(cfgo1(Arg1()+MemData)) {
		ACC = 1;
		return; }
	Ptr = sA0p;
	STKargs();
	stack_index(0);
	memcpy(savjmp, (Uchar*)&jmphome, sizeof(savjmp));
	cfgo2();
	RPend(0);
	memcpy((Uchar*)&jmphome, savjmp, sizeof(savjmp));
	free(MemCode);
	SP = sSP;	PC = sPC;	MemCode = sMC;	LibFunSiz = sLFS;
	MemData = MemCode + sMD;
}
void LIBexit(void)
{
	Ushort i;
	for(i=3; i < (OSFILES+RDFILES); ++i)
		Xclose(i+1);
//?	ACC = Arg0();
	longjmp(jmphome, 255);
}
void LIBhalt(void)
{
	exit(Arg0());
}

void LIBchdir(void)
{
	ACC = _chdir(Arg0()+MemData);
}
void LIBmkdir(void)
{
	ACC = _mkdir(Arg0()+MemData);
}
void LIBrmdir(void)
{
	ACC = _rmdir(Arg0());
}
void LIBgetdir(void)
{
	if(!(ACC = getcwd(Ptr = Buffer, 128) ? 0 : 255)) {
		if(Ptr[1] == ':')
			Ptr += 3;
		strcpy(Arg0()+MemData, Ptr); }
}
void LIBget_drive(void)
{
	ACC = getdrive()-1;
}
void LIBset_drive(void)
{
	Ulong i;
	Uchar temp[4];
	if((ACC = Arg0()) < 26) {
		temp[0] = ACC + 'A';
		temp[1] = ':';
		temp[2] = 0;
		chdir(temp); }
	ACC = 0;
	i = _getdrives();
	while(i) {
		++ACC;
		i >>= 1; }
}

Ulong	FFhandle;
Ushort	FFattr;
struct	_finddata_t FFdata;
Uchar	Mdays[] = {
//	Jan	Feb	Mar	Apr	May	Jun Jul	Aug	Sep	Oct	Nov	Dec
	1,	1,	1,	0,	1,	0,	1,	1,	0,	1,	0,	1 };
#define	DBGtime(a)	//Pr a;
Ushort FFCVtime(Ushort *date)
{
	Ulong i, j, s, t;
	Uchar lp;

//	t	-= 315547200;
//?	t = FFdata.time_write - 315547200;
	t = FFdata.time_write - (315547200+3600);

	j = 1980;
a2:	s = (60*60*24)*365;
	lp = 0;
	if(j % 4)	goto cy;		// Not divisible by 4
	if(j % 100)	goto ly;		// Not divisibke by 100
	if(j % 400)	goto cy;		// Not divisible by 400
ly:	s += (60*60*24);	// Extra day
	lp = 7;
cy:	if(s < t) {
		t -= s;
		++j;
		goto a2; }
	DBGtime(("  %u", j))
	i = (j - 1980) << 9;
	j = 0;
a3:	if(j == 1)	// Feb
		s = lp ? (60*60*24*29) : (60*60*24*28);
	else
		s = Mdays[j] ? (60*60*24*31) : (60*60*24*30);
	if(s < t) {
		t -= s;
		++j;
		goto a3; }
	DBGtime(("/%02u", j+1))
	i |= (j + 1) << 5;
	j = 0;
a4:	s = (60*60*24);
	if(s < t) {
		t -= s;
		++j;
		goto a4; }
	DBGtime(("/%02u", j+1))
	i += (j+1);
//?Pr("[%04x]", i);
	*date = i;
	i = j = 0;
a5:	s = (60*60);
	if(s < t) {
		t -= s;
		++j;
		goto a5; }
	DBGtime((" %02u:%02u:%02u\n", j, t / 60,  t % 60))
	i = (j << 11) + ((t / 60) << 5) + ((t % 60) >> 1);
//?Pr("[%04x]", i);
	return i;
}

void LIBfind_close(void)
{
	if(FFhandle > 1)
		_findclose(FFhandle);
	FFhandle = 0;
}
Ushort FindFile1(Ushort b)
{
	if(b) {
		LIBfind_close();
		FFhandle = _findfirst(Arg(b)+MemData, &FFdata); }
	if(FFhandle == -1) {
er:		return ACC = 255; }
	if(!b) {
a1:		if(_findnext(FFhandle, &FFdata)) {
			LIBfind_close();
			goto er; } }
	if(FFattr & 0x40)
		goto a2;
	if(!(FFattr & 0x3F)) {
		if(!(FFdata.attrib & 0x01E))	// Not Dir/Vol/Sys/Hidden
			goto a2; }
	if(!(FFdata.attrib & FFattr))
		goto a1;
a2:	return ACC = 0;
}
void FindFile2(void)
{
	Ushort da, ti;
	ti = FFCVtime(&da);
	WRmem2(Arg0(), da);					// Date
	WRmem2(Arg1(), ti);					// Time
	WRmem2(Arg2(), FFdata.attrib);		// Attrs
	WRmem2(Arg3(), FFdata.size);		// SizeL
	WRmem2(Arg(4), FFdata.size >> 16);	// SizeH
	strcpy(Arg(5)+MemData, FFdata.name);
}
void FindFile3(Ushort a)
{
	Ushort da, ti;
	ti = FFCVtime(&da);
	WRmem2(a+0, da);					// 0	Ushort date;
	WRmem2(a+2, ti);					// 2	Ushort time;
	WRmem2(a+4, FFdata.attrib);			// 4	Uchar attrib;
	WRmem2(a+6, FFdata.size);			// 6	Ushort size[2];
	WRmem2(a+8, FFdata.size >> 16);		// 8	""
	strcpy(MemData+a+10, FFdata.name);	// 10	Uchar name[];
}
void LIBfind_first(void)	// 7pat,6atr,5nam,4sh,3sk,2at,1ti,0da
{
	FFattr = Arg(6);
	if(!FindFile1(7))
		FindFile2();
}
void LIBfind_next(void)
{
	if(!FindFile1(0))
		FindFile2();
}
void LIBfindfirst(void)		// 2pat,1res,0attr
{
	FFattr = Arg0();
	if(!FindFile1(2))
		FindFile3(Arg1());
}
void LIBfindnext(void)
{
	if(!FindFile1(0))
		FindFile3(Arg0());
}

void LIBmemchr(void)
{
	Ushort a, l;
	Uchar c;
	a = Arg2();
	c = Arg1();
	l = Arg0();
	while(l) {
		if(MemData[a] == c) {
			ACC = a;
			return; }
		++a;
		--l; }
	ACC = 0l;
}
void LIBmemcmp(void)
{
	Ushort a1, a2, l;
	a1 = Arg2();
	a2 = Arg1();
	l = Arg0();
	while(l) {
		if(MemData[a1] < MemData[a2])		{	ACC = 0xFFFF;	return; }
		if(MemData[a1++] > MemData[a2++])	{	ACC = 1;		return; }
		--l; }
	ACC = 0;
}
void LIBstrdup(void)
{
	Uchar *p;
	p = Arg0()+MemData;
	if(ACC = Malloc(strlen(p)))
		strcpy(MemData+ACC, p);
}
void LIBstrrev(void)
{
	Ushort s, p;
	Uchar c;

	p = s = Arg0();
	while(MemData[p])
		++p;
	while(s < p) {
		c = MemData[s];
		MemData[s++] = MemData[--p];
		MemData[p] = c; }
}
void LIBstrset(void)
{
	Ushort p;
	Uchar c;
	p = Arg1();	c = Arg0();
	while(MemData[p])
		MemData[p++] = c;
}
void LIBstrstr(void)
{
	Ushort s1, s2;
	s1 = Arg1();	s2 = Arg0();
	while(MemData[s1]) {
		if(Strbeg(MemData+s1, MemData+s2)) {
			ACC = s1;
			return; }
		++s1; }
	ACC = 0;
}
void LIBMemReadCode1(void)
{
	ACC = MemCode[Arg0()];
}
void LIBMemReadCode2(void)
{
	Ushort a;	a = Arg0();
	ACC = (MemCode[a+1] << 8) | MemCode[a];
}

// Far segments
Ulong far_seg(Ushort seg, Ushort adr)
{
	Ulong off;
	off = ((seg & 0xFFF0)<<4) + adr;
	if((seg = (seg & 15) - 1) >= FARSEG) {
rz:		return 0; }
	if((FarSiz[seg]<<4) <= off) {
		goto rz; }
	Ptr = FarSeg[seg];
	return off+1;
}
void LIBalloc_seg(void)
{
	Ulong s;
	Ushort i;
	s = Arg0();
	for(i=0; i < FARSEG; ++i) {
		if(!FarSeg[i]) {
			if(FarSeg[i] = malloc(s << 4)) {
				FarSiz[i] = s;
				ACC = i + 1;
				return; }
			break; } }
	ACC = 0;
}
void LIBfree_seg(void)
{
	if(far_seg(Arg0(), 0)) {
		free(Ptr);
		ACC = 0;
		return; }
	ACC = 255;
}
void LIBresize_seg(void)
{
	Ulong a, s;
	Ushort se;
	ACC = 255;
	if(a = far_seg(se = Arg0(), 0)) {
		Ptr = malloc((s = Arg1()) << 4);
		if(FarSiz[--se] < s)
			s = FarSiz[se];
		memcpy(Ptr, FarSeg[se], s << 4);
		free(FarSeg[se]);
		FarSeg[se] = Ptr;
		ACC = 0; }
}

void LIBpoke(void)
{
	Ulong a;
	if(a = far_seg(Arg2(), Arg1()))
		Ptr[a-1] = Arg0();
}
void LIBpokew(void)
{
	Ulong a;	Ushort v;
	if(a = far_seg(Arg2(), Arg1())) {
		Ptr[a-1] = v = Arg0();
		Ptr[a] = v >> 8; }
}
void LIBpeek(void)
{
	Ulong a;
	ACC = 0;
	if(a = far_seg(Arg1(), Arg0()))
		ACC = Ptr[a-1];
}
void LIBpeekw(void)
{
	Ulong a;
	ACC = 0;
	if(a = far_seg(Arg1(), Arg0()))
		ACC = (Ptr[a] << 8) | Ptr[a-1];
}
void LIBcopy_seg(void)
{
	Uchar *pd;
	Ushort s;
	Ulong a;
	if(a = far_seg(Arg0(), Arg1())) {
		pd = Ptr+a-1;
		if(a = far_seg(Arg2(), Arg3())) {
			Ptr += (a-1);
			s = Arg(4);
			while(s)
				*pd++ = *Ptr++; } }
}

void LIBsetCapture(void)
{
	Ushort f, g;
	if(f=g=Arg0()) {
		if(--f < 3)		return;
		if(f < OSFILES) {
			CapFile = OSfiles[f] ? g : 0;
			return; }
		if((f -= OSFILES) < RDFILES) {
			CapFile = RDcsec[f] ? g : 0;
			return; } }
	CapFile = 0;
}

void StNum(Uchar *dst, Ulong n)
{
	Ushort sp;
	Uchar stk[16];
	sp = 0;
	do {
		stk[sp++] = (n % 10) + '0'; }
	while(n /= 10);
	while(sp)
		*dst++ = stk[--sp];
	*dst = 0;
}
// Startup an RProc
void LIBRPstart(void)	// nam, siz
{
	int Hx, H[2];
	Ushort i, siz;
	Uchar c, *nam, ts1[16], ts2[16];

	for(i=0; i < RPS; ++i) {
		if(!HrL[i])
			goto a1; }
	goto r0;
a1:	nam = Arg1()+MemData;
	siz = Arg0();
	if(_pipe(H, siz, _O_BINARY))
		goto r0;
	HrL[i] = Hr = H[0];
	Hx = H[1];
//Pr("M[%u %u", H[0], H[1]);
	if(_pipe(H, siz, _O_BINARY))
		goto r1;
	HwL[i] = Hw = H[1];
//Pr(" %u %u]", H[0], H[1]);
	StNum(ts1, H[0]);
	StNum(ts2, Hx);
	Ptr = 0;
	do {
		c = Home(Buffer, nam, ".EXE");
//Pr("Sp'%s'%s'%s'\n", Buffer, ts1, ts2); //if(0) {
		if(_spawnl(_P_NOWAIT, Buffer, Buffer, ts1, ts2, 0) != -1) {
			ACC = i+1;
			return; } }
	while(c & 0xF0);
	_close(Hw);
r1:	_close(Hr);
r0:	ACC = 0;
}

// Select an RProc
Ushort RPsel(Ushort i)
{
	--i;
	if(i >= RPS) {
er:		return 255; }
	if(!(Hr = HrL[i]))
		goto er;
	Hw = HwL[i];
	return 0;
}
// End an RProc
void RPend(Ushort i)
{
	Ushort j, siz;
	j = i ? i+1 : RPS;
	while(i < j) {
		if(!RPsel(i)) {
			siz = 0xFFFF;
			_write(Hw, &siz, SIZ);
			HrL[i] = HwL[i] = 0; }
		++i; }
}
void LIBRPend(void)
{
	RPend(Arg0());
}
// Write to an RPC task
void LIBRPwrite(void)	// index,buf,siz
{
	Ushort siz, w1, w2;
	Uchar *buf;
	siz = Arg0();
	buf=Arg1()+MemData;
	ACC = 0;
	if(RPsel(Arg2()))	return;
	w1 = _write(Hw, &siz, SIZ);
	w2 = _write(Hw, buf, siz);
	ACC = siz;
}

// Read From an RPC task
void LIBRPread(void)	// index,buf,siz
{
	Ushort i, s, siz;
	Uchar x;
	siz = Arg0();
	if(RPsel(Arg2()))	{
		ACC = 0;
		return; }
	i = _read(Hr, &s, SIZ);
	if(i != SIZ)
		Error("!:RPread(%u)", i);
	if(s > siz)
		Error("!:RPread(%u %u)", s, siz);
	i = _read(Hr, Arg1()+MemData, s);
	if(i != s)
		Error("!:RPread(%u %u)", s, i);
	ACC = s;
}

extern void LIBinit(void);
// Library function table
Ushort(*LibFuns[])(void) = {
	&LIBinit, &LIBexit,
	&LIBfopen, &LIBfclose, &LIBfflush, &LIBrewind, &LIBfseek, &LIBftell,
	&LIBfput, &LIBfget, &LIBfwrite, &LIBfread,
	&LIBputchar, &LIBputc, &LIBfputs, &LIBgetchar, &LIBgetc, &LIBfgets,
	&LIB_format_, &LIBprintf, &LIBfprintf, &LIBsprintf,
	&LIBscanf, &LIBfscanf, &LIBsscanf,
	&LIBdelete,
	&LIBatoi, &LIBatox, &LIBitoa,
	&LIBisascii, &LIBisalpha, &LIBislower, &LIBisupper, &LIBisdigit,
	&LIBisxdigit, &LIBisalnum, &LIBisgraph, &LIBiscntrl, &LIBispunct,
	&LIBisprint, &LIBisspace,
	&LIBstrcpy, &LIBstrncpy, &LIBstrcat, &LIBstrcmp, &LIBstrbeg, &LIBstrlen,
	&LIBstrchr,
	&LIBmemset, &LIBmemcpy,
	&LIBmalloc,	&LIBcalloc, &LIBfree, &LIBcoreleft,
	&LIBlongset, &LIBlongcpy, &LIBlongtst, &LIBlongcmp,
	&LIBlongadd, &LIBlongsub, &LIBlongmul, &LIBlongdiv,
	&LIBlongshl, &LIBlongshr, &LIBltoa, &LIBatol,
	&LIBmin, &LIBmax, &LIBabs, &LIBsqrt,
	&LIBtoupper, &LIBtolower, &LIBstrupr, &LIBstrlwr,
	&LIBconcat,
	&LIBsetjmp, &LIBlongjmp,
	&LIBget_date, &LIBget_time, &LIBgetenv,
	&LIBdelay,
	&LIBbeep,
	&LIBkbget, &LIBkbhit, &LIBkbtst,
	&LIBVcleol, &LIBVcleos, &LIBVclscr, &LIBVcursor, &LIBVopen, &LIBVclose,
	&LIBVgetc, &LIBVgetk, &LIBVgets, &LIBVputc, &LIBVputs, &LIBVprintf,
	&LIBVcolor, &LIBVFcolor, &LIBVBcolor,
	&LIBRDsetup,
	&LIBabort,
	&LIBsystem,
	&LIBexec, &LIBhalt,
	&LIBchdir, &LIBgetdir, &LIBfind_first, &LIBfind_next, &LIBfind_close,
	&LIBfindfirst, &LIBfindnext,
	&LIBmemchr, &LIBmemcmp, &LIBstpcpy, &LIBstrdup, &LIBstrrev, &LIBstrset,
	&LIBstrstr, &LIBVgotoxy,
	&LIBMemReadCode1, &LIBMemReadCode2,
	&LIBalloc_seg, &LIBfree_seg, &LIBpoke, &LIBpokew, &LIBpeek, &LIBpeekw,
	&LIBmkdir, &LIBrmdir, &LIBget_drive, &LIBsetCapture,
	&LIBfreopen, &LIBrealloc, &LIBrename, &LIBcopy_seg, &LIBresize_seg,
	&LIBset_drive,
	&LIBRPstart, &LIBRPend, &LIBRPwrite, &LIBRPread,
	&LIBputs, LIBgets,
//	,&LIBMemDump, &LIBStkDump
	};
//!LIB!	getc	fgetc
//!LIB!	putc	fputc
//!LIB!	fputs	puts
//!LIB!	fgets	gets
//!LIB!	delete	remove	unlink
//!LIB!	memcpy	memmove
//!LIB!	delay	sleep
//!LIB!	chdir	cd
//!LIB! $FF00	nargs

// Initialize library
void LIBinit(void)
{
	UniMem = INDEX;
	LibFunSiz = sizeof(LibFuns)/sizeof(LibFuns[0]);
	OSfiles[0] = stdin;
	OSfiles[1] = stdout;
	OSfiles[2] = stderr;
//Pr("in:%08x ot:%08x er:%08x\n", stdin, stdout, stderr);
//	Pr(" %u\n", UniMem);
}	
