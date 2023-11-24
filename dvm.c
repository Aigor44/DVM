/*
 * DVM virtual machine
 *
 * Compile with LCCwin32: lc -e5 -nw DVM.c -s
 *
 * Dave Dunfield   -   https://dunfield.themindfactory.com
 */

#include <stdio.h>
#include <stdlib.h>
#include <setjmp.h>
#include <conio.h>
#include <time.h>
#include <io.h>
#include <sys/stat.h>

#define	HDRLEN	128

#define	DVMLIB	0		// Expected library version

#define	Ulong	unsigned
#define	Ushort	unsigned short
#define	Uchar	unsigned char
#define	Sshort	short int

// Make sure LOADADR matches the starting address configured in library
#define	LOADADR	0x0000		// Default load address is 0x1000

#define	BYTE_OP	0x08		// Bit in opcode indicating byte operand
#define	EQ		0x01		// Bit in cflags indicating ==
#define	ULT		0x02		// Bit in cflags indicating Ushort <
#define	UGT		0x04		// Bit in cflags indicating Ushort >
#define	SLT		0x08		// Bit in cflags indicating signed <
#define	SGT		0x10		// Bit in cflags indicating signed >

#define	Fget(d,s,f)	fread(d,1,s,f)
#define Fput(d,s,f)	fwrite(d,1,s,f)

/*
 * Public global variables
 */
Ushort
	ACC,					// C-FLEA accumulator
	INDEX,					// C-FLEA Index register
	SP,						// C-FLEA Stack Pointer
	PC;						// C-FLEA Program Counter
Uchar
	*MemCode,
	*MemData;

/*
 * Private global variables
 */
static Ulong
	FMTarg;					// Argument to _Format_
static Ushort
	Alt,					// Alternate result from DIV
	Address,				// Address holding register
	LibFunSiz,
	HomeEnd;
static Uchar
	*Ptr,
	*ArgV,
	*HomeDir,
	Atype,					// Type of memory address
	opcode,					// current command opcode
	cflags,					// Compare result flags
	Buffer[128];			// General buffer
jmp_buf
	jmphome;

extern Ushort(*LibFuns[])(void);

/*
 * Function prototypes
 */
Ushort cf_run(void);			// Main C-FLEA execution function
void cf_output(Ushort port);	// Called to output to an I/O port
void cf_input(Ushort port);		// Called to input from an I/O port
void UPend(Ushort i);			// end RPcs

/*
 * Shared formated output
 */
Ulong RDarg4(void)	// Read a 4 byte argument
{
	return	*(Ulong*)FMTarg;
}
Ulong RDarg2(void)	// Read a two byte argument
{
	return (MemData[FMTarg+1]<<8) | MemData[FMTarg];
}
// Format to string routine, format operands are passed
// as a pointer to the calling functions argument lists.
Ushort _Format_(Uchar *outptr, Uchar mt)
{
	Ulong width, value, i;
	Uchar left, zero, c, *iptr, *optr, *ptr, outstk[17];

	if(mt)
		iptr = MemData + RDarg2();
	else
		iptr = (Uchar*)RDarg4();
	optr = outptr;						// So we can return length
	while(c = *iptr++) {
		if(c == '%') {					// format code
			c = *iptr++;
			*(ptr = &outstk[16]) = left = width = value = i = 0;
			zero = ' ';					// Assume pad with ' '
			if(c == '-') {				// left justify
				left = 255;
				c = *iptr++; }
			if(c == '0')				// pad with '0'
				zero = '0';
			while((c >= '0') && (c <= '9')) {	// Field width
				width = (width * 10) + (c - '0');
				c = *iptr++; }

			if(mt) {
				FMTarg -= 2;
				value = RDarg2(); }
			else {
				FMTarg += 4;
				value = RDarg4(); }

			switch(c) {
				case 'd' :				// decimal (signed)
					if((value & 0x8000) && mt)
						value |= 0xFFFF0000;
					if(value & 0x80000000) {
						value = 0-value;
						*optr++ = '-';
						if(width) --width; }
				case 'u' :				// unsigned
					i = 10;
					break;
				case 'x' :				// hexidecimal
					i = 16;
					break;
				case 'o' :				// octal
					i = 8;
					break;
				case 'b' :
					i = 2;
					break;
				case 'c' :				// character
					*--ptr = value;
					break;
				case 's' :				// string
					if(mt)
						ptr = (Uchar*)(value + MemData);
					else
						ptr = (Uchar*)value;
					break;
				default:				// all others
					if(mt)
						FMTarg += 2;
					else
						FMTarg -= 4;
					*--ptr = c; }

			if(i)		// for all numbers, generate the ASCII string
				do {
					if((c = (value % i) + '0') > '9')
						c += 7;
					*--ptr = c; }
				while(value /= i);

			if(width && !left) {		// pad if right justify enabled
				for(i = strlen(ptr); i < width; ++i)
					*optr++ = zero; }

			i = 0;						// move in data
			value = width - 1;
			while((*ptr) && (i <= value)) {
				*optr++ = *ptr++;
				++i; }

			if(width && left) {			// pad if left justify enabled
				while(i < width) {
					*optr++ = zero;
					++i; } } }
		else				// not a format code, simply copy the character
			*optr++ = c; }

	*optr = 0;
	return optr - outptr;
}

// Formated print
Ushort Pr(Uchar *format, ...)
{
	Ulong fa;
	Ushort l;
	Uchar buf[128];
	fa = FMTarg;
	FMTarg = (Ulong)&format;
	l = _Format_(buf, 0);
	FMTarg = fa;
	fputs(buf, stdout);
	return l;
}

void Error(Uchar *format, ...)
{
	Uchar *p, buf[128];
	FMTarg = (Ulong)&format;
	_Format_(p = buf, 0);
	if(*p == '!') ++p;
	if(*p==':') fputs("DIE: ", stdout);
	fputs(p, stdout);
	if(*buf == '!')
		Pr(" - A=%04x I=%04x P=%04x S=%04x", ACC, INDEX, PC, SP);
	RPend(0);	//
	exit(-1);
}

/*
 * C-FLEA virtual machine
 */
#define	read_code(address)			MemCode[address]
#define	read_data(address)			MemData[address]
#define	write_data(address, data)	MemData[address] = data
Uchar read_mem(Ushort address)
{
	if(Atype) return MemData[address];
	return MemCode[address];
}

/*
 * Compute the address of the current instructions operand
 */
static void cf_get_address(void)
{
	switch(opcode & 7) {
		case 0 :		// Immediate reference
			Address = PC++;
			Atype = 0;
			return;
		case 1 :		// Direct address
			Address = read_code(PC++);
			Address |= read_code(PC++) << 8;
			break;
		case 2 :		// Indirect - no offset
			Address = INDEX;
			break;
		case 3 :		// Indirect with offset
			Address = INDEX + read_code(PC++);
			break;
		case 4 :		// Indirect from SP with offset
			Address = SP + read_code(PC++);
			break;
		case 5 :		// On top of stack, remove
			Address = SP;
			SP += 2;
			break;
		case 6 :		// Indirect through top of stack, remove
			Address = read_data(SP++);
			Address |= read_data(SP++) << 8;
			break;
		case 7 :
			Address = read_data(SP);
			Address |= read_data(SP+1) << 8; }
	Atype = 255;
}

/*
 * Main C-FLEA virtual machine execution function
 */
Ushort cf_run(void)
{
	Ushort operand, t1, t2;
	Uchar ccc;

	for(;;) {
		opcode = read_code(PC++);
		if(opcode < 0x98) {		// Catagory 1 instruction
			cf_get_address();
			operand = read_mem(Address);
			if(!(opcode & BYTE_OP)) {
				if(!(opcode & 7))
					++PC;
				operand |= read_mem(Address+1) << 8; }
			switch(opcode & 0xF0) {
			case 0x00 :	ACC = operand;					break;	// LD
			case 0x10 : ACC += operand;					break;	// ADD
			case 0x20 : ACC -= operand;					break;	// SUB
			case 0x30 : ACC *= operand;					break;	// MUL
			case 0x40 :
				Alt = ACC % operand; ACC /= operand;	break;	// DIV
			case 0x50 : ACC &= operand;					break;	// AND
			case 0x60 :	ACC |= operand;					break;	// OR
			case 0x70 :	ACC ^= operand;					break;	// XOR
			case 0x80 :											// CMP
				if(ACC == operand) {
					cflags = EQ;
					ACC = 1; }
				else {
					cflags = (ACC < operand) ? ULT : UGT;
					cflags |= ((Sshort)ACC < (Sshort)operand) ? SLT : SGT;
					ACC = 0; }
				break;
			case 0x90 :	INDEX = operand; }						// LDI
		} else if (opcode < 0xC8) {		// Catagory 2 instruction
			cf_get_address();
			switch(opcode & 0xF8) {
			case 0x98 :	INDEX = Address;				break;	// LEAI
			case 0xA0 :	write_data(Address+1, ACC >> 8);		// ST
			case 0xA8 :	write_data(Address, ACC);		break;	// STB
			case 0xB0 :	write_data(Address, INDEX);				// STI
						write_data(Address+1, INDEX >> 8); break;
			case 0xB8 : ACC >>= read_mem(Address);		break;	// SHR
			case 0xC0 :	ACC <<= read_mem(Address); }			// SHL
		} else switch(opcode) {		// Catagory 3 instruction
		case 0xC8 :	ACC = (cflags & (SLT))	  ? 1 : 0;	break;	// LT
		case 0xC9 : ACC = (cflags & (SLT|EQ)) ? 1 : 0;	break;	// LE
		case 0xCA : ACC = (cflags & (SGT))	  ? 1 : 0;	break;	// GT
		case 0xCB : ACC = (cflags & (SGT|EQ)) ? 1 : 0;	break;	// GE
		case 0xCC : ACC = (cflags & (ULT))	  ? 1 : 0;	break;	// ULT
		case 0xCD : ACC = (cflags & (ULT|EQ)) ? 1 : 0;	break;	// ULE
		case 0xCE : ACC = (cflags & (UGT))	  ? 1 : 0;	break;	// UGT
		case 0xCF : ACC = (cflags & (UGT|EQ)) ? 1 : 0;	break;	// UGE
		case 0xD0 :												// JMP
		doljmp:		Address = read_code(PC+1) << 8;
					PC = read_code(PC) | Address;
					break;
		case 0xD1 : if(!ACC) goto doljmp; PC+=2;		break;	// JZ
		case 0xD2 :	if(ACC)  goto doljmp; PC+=2;		break;	// JNZ
		case 0xD3 :
		dosjmp:		Address = read_code(PC++);					// SJMP
					if(Address & 0x80) Address |= 0xFF00;
					PC += Address;						break;
		case 0xD4 :	if(!ACC) goto dosjmp; ++PC;			break;	// SJZ
		case 0xD5 :	if(ACC)  goto dosjmp; ++PC;			break;	// SJNZ
		case 0xD6 :	PC = ACC;							break;	// IJMP
		case 0xD7 :												// SWITCH
			Address = INDEX;
			for(;;) {
				t1 = read_code(Address++);
				t1 |= read_code(Address++) << 8;
				t2 = read_code(Address++);
				t2 |= read_code(Address++) << 8;
				if(!t1) {
					PC = t2;
					break; }
				if(t2 == ACC) {
					PC = t1;
					break; } }
			break;
		case 0xD8 :												// CALL
			operand = PC + 2;
			write_data(--SP, operand >> 8);
			write_data(--SP, operand);
			goto doljmp;
		case 0xD9 :												// RET
			PC = read_data(SP++);
			PC |= read_data(SP++) << 8;					break;
		case 0xDA : SP -= read_code(PC++);				break;	// ALLOC
		case 0xDB :	SP += read_code(PC++);				break;	// FREE
		case 0xDC :												// PUSHA
			write_data(--SP, ACC >> 8);
			write_data(--SP, ACC);						break;
		case 0xDD :												// PUSHI
			write_data(--SP, INDEX >> 8);
			write_data(--SP, INDEX);						break;
		case 0xDE : SP = ACC;							break;	// TAS
		case 0xDF : ACC = SP;							break;	// TSA
		case 0xE0 : ACC = 0;							break;	// CLR
		case 0xE1 : ACC = ~ACC;							break;	// COM
		case 0xE2 : ACC = -ACC;							break;	// NEG
		case 0xE3 : ACC = !ACC;							break;	// NOT
		case 0xE4 : ++ACC;								break;	// INC
		case 0xE5 : --ACC;								break;	// DEC
		case 0xE6 : INDEX = ACC;						break;	// TAI
		case 0xE7 : ACC = INDEX;						break;	// TIA
		case 0xE8 : INDEX += ACC;						break;	// ADAI
		case 0xE9 : ACC = Alt;							break;	// ALT
		case 0xEA : cf_output(read_code(PC++));			break;	// OUT
		case 0xEB : cf_input(read_code(PC++));			break;	// IN
		default: return opcode; } }			// Unknown opcode
}

/*
 * This function is called in response to an OUT instruction
 */
void cf_output(Ushort port)
{
	switch(port) {
		case 0 :	// Console output
			putc(ACC, stdout);
			return;
		// More output ports can be defined here
		}

	Error("!:Output port %02x", port);
}

/*
 * This function is called in response to an IN instruction
 */
void cf_input(Ushort port)
{
	switch(port) {
		case 0 :	// Console input
			ACC = getch();
			return;
		// More input ports can be defined here
		}

	Error("!:Input port %02x", port);
}


// Fetch argument (0=Last)
Ushort Arg(Ushort i)
{
	i = (i*2) + SP;
	return (MemData[i+1] << 8) | MemData[i];
}
Ushort Arg0()	{	return Arg(0);	}
Ushort Arg1()	{	return Arg(1);	}
Ushort Arg2()	{	return Arg(2);	}
Ushort Arg3()	{	return Arg(3);	}

/*
 * Misc. function to support various ways of runing a VM
 */
// Place a string on the virtual stacl
void stack_string(Uchar *s)
{
	SP -= (strlen(s)+1);
	strcpy(MemData+SP, s);
}
// Place a word value on the virtual stack
void stack_value(Ushort v)
{
	MemData[--SP] = v >> 8;
	MemData[--SP] = v;
}
// Index the virtual stacked strings and create: argc, argv
void stack_index(Ushort t)
{
	Ushort i, s, sv[50];
	i = SP;
	s = 0;
	while(i != t) {
		if(i < SP)
			Error("!:ArgErr");
		sv[s++] = i;
		while(MemData[i++]); }
	for(i=0; i < s; ++i)
		stack_value(sv[i]);
	stack_value(s);
	stack_value(SP+2);
}

Ushort Home(Uchar *dst, Uchar *nam, Uchar *ext)
{
	Ushort i, j, k, m;
	Uchar c;

	i = j = k = m = 0;
	if(nam) {
a1:		switch(nam[i++]) {
		case ':':
		case'\\':
			j = i;
			k = 0;
			goto a1;
		case '.':
			k = i;
		default	:	goto a1;
		case 0	:	; }
		i = 0;
		if(j) {
			m = 15;
			goto ex; } }
	if(!Ptr)
		Ptr = HomeDir;
a9:	if(c = *Ptr)
		++Ptr;
	switch(c) {
	default	:	dst[i++] = c;	goto a9;
	case ';':	m = 255;
	case 0	:	; }
	if(i) switch(dst[i-1]) {
		default	: dst[i++] = '\\';
		case ':':
		case'\\': ; }
ex:	if(nam) {
		while(c = *nam++)
			dst[i++] = c; }
	if(ext) {
		if(!k) {
			while(c = *ext++)
				dst[i++] = c; } }
	dst[i] = 0;
	return m;
}

//FILE *Xfopen(Uchar *a, Uchar *b) { Pr("Fo'%s'%s'\n", a, b);
//	return 0;
//	return fopen(a, b); }
// Load a CF VM
Ushort cfgo1(Uchar *nam)
{
	Ulong l, lp;
	Ushort i, j;
	Uchar c;
	FILE *fp;

	Ptr = ""; Home(Buffer, nam, ".DVM");
	if(fp = fopen(Buffer, "rb"))	goto a1;
	Ptr = 0;
	do {
		i = Home(Buffer, nam, ".DVM");
		if(fp = fopen(Buffer, "rb"))	goto a1; }
	while(i & 0xF0);
	fputs(Buffer, stdout);
	fputs(": unable to open!\n", stdout);
	return 255;

a1:	ACC = INDEX = SP = PC = lp = 0;
	i = l = 0;
a5:	c = getc(fp);
	Fget(&j, 2, fp);
	if((c == 'D') && (j == 0x4D56)) {	// DVM protected
		for(j=0; j < (HDRLEN-3); ++j)
			getc(fp);
		goto a5; }
	if(c != DVMLIB)
		Error("!:%s Ilib%u, DVM Ilib%u", Buffer, c, DVMLIB);

	l = j + 65536;
	if(!(MemCode = (Uchar*)malloc(l))) {
a6:		Error(":%s load failed!", Buffer); }
	MemData = MemCode + j;
	while((i = getc(fp)) <= 0xFF)		// Load in executable image
		MemCode[lp++] = i;
	fclose(fp);						// Finished with file
	stack_string(Buffer);
	while(lp < SP)
		MemCode[lp++] = 0;
	LibFunSiz = 1;
	return 0;	ACC = INDEX = SP = PC = lp = 0;
}

// Execute a loaded virtual machine
void cfgo2(void)
{
	Ushort i;

	if(setjmp(jmphome))
		return;
rn:	switch(i = cf_run()) {
	case 0xFF:
		i = read_code(PC++);
		if(i >= LibFunSiz)
			Error("!:SysCall %u", i);
		LibFuns[i]();
		goto rn; }
	Pr("DVM: Unknown opcode %02x at %04x\n", i, PC-1);
}

// Parse a string with possible quote qualifiers
Ushort parse(unsigned char *d)
{
	Ushort l;
	Uchar c, q;
	l = q = 0;
a1:	switch(c = *Ptr) {
	case ' ':
	case'\t': ++Ptr; goto a1;
	case 0 : return 0;
	case '"':
		q = c;
		++Ptr; }
a2:	switch(c = *Ptr) {
	case ' ' :
	case '\t':
		if(!q)
			break;
	default:
		++Ptr;
		if(c == q)
			break;
		d[l++] = c;
		goto a2;
	case 0 : ; }
	d[l] = 0;
	return l;
}

static Uchar Notice[] = {
"DVM for personal use - if you see this relating to any company/product,\n\
please contact me: https://dunfield.themindfactory.com\n" };

/*
 * Demo program to show use of the DVM module.
 */
main(Ushort argc, Uchar *argv[])
{
	Ushort i;

	// Attempt to learn executable home directory prefix
	HomeDir = argv[0];
	HomeEnd = i = 0;
a1:	switch(HomeDir[i++]) {
	case'\\':
	case ':': ACC = i;
	default : goto a1;
	case 0 : HomeDir[ACC] = 0; }
	if(Ptr = getenv("DVM"))
		HomeDir = Ptr;

	if(argc < 2) {
		fputs(Notice, stderr);
		fputs("\nUse: dvm <file>[.DVM] [args]\n", stdout);
		Error("\nIlib: %u\n", DVMLIB); }

	if(cfgo1(argv[1]))
		goto ex;
	for(i=2; i < argc; ++i) {
		stack_string(argv[i]); }
	stack_index(0);
	cfgo2();
ex:	;
	RPend(0);	//
}

#include "dvmvideo.h"
#include "vcons.ch"
#include "lib.ch"
